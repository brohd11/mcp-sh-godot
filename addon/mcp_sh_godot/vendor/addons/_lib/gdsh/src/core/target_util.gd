extends RefCounted
## Resolve script and node targets and enumerate their members. Script paths accept a global
## class name, a res://, user:// or absolute OS path, or a path relative to ctx.cwd.
## Member access walks through Script-valued constants. Hosts may supply a base Script directly.

const Options = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/options.gd")

const UClassDetail = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/util_r/src/object/class_detail.gd")

## Scripts loaded from outside the project, by path: [source hash, script]. Kept like res://
## scripts are in Godot's cache, so timers, signals and lambdas a call leaves behind outlive it
## (a freed script's lambdas crash when called). Rebuilt when the file changes.
static var _outside_scripts := {}

const USAGE_TEMPLATE = \
"Usage: script <class|path.gd> %s
Usage: node <node path> %s"


static func get_usage_string(preamble:String, commands:String):
	return preamble + "\n" + USAGE_TEMPLATE % [commands, commands]


## Pure classification shared by dispatch, resolution and completion. Only the final path
## component may contain the .gd/member boundary; dotted directories are ordinary paths.
static func parse_script_target(text:String) -> Dictionary:
	var file = text.get_file()
	var boundary = file.to_lower().rfind(".gd.")
	var is_file = boundary >= 0 or file.get_extension().to_lower() == "gd"
	if boundary >= 0:
		var end = text.length() - file.length() + boundary + 3
		return {"base": text.left(end), "members": text.substr(end + 1), "has_members": true, "is_file": true}
	if is_file or text.contains("/") or text.is_absolute_path():
		return {"base": text, "members": "", "has_members": false, "is_file": is_file}
	var dot = text.find(".")
	return {"base": text if dot < 0 else text.left(dot),
			"members": "" if dot < 0 else text.substr(dot + 1), "has_members": dot >= 0, "is_file": false}


static func _load_script(path:String):
	var localized = ProjectSettings.localize_path(path)
	if localized.begins_with("res://") or localized.begins_with("user://"):
		var resource = load(localized) if ResourceLoader.exists(localized) else null
		return resource if resource is Script else null
	if not FileAccess.file_exists(path):
		return null
	var source = FileAccess.get_file_as_string(path)
	var cached = _outside_scripts.get(path)
	if cached != null and cached[0] == source.hash():
		return cached[1]
	var script = GDScript.new()
	script.source_code = source
	# Without a path, relative preloads/extends resolve against gdscript:// and fail.
	script.set_path_cache(path)
	if script.reload() != OK:
		return null
	_outside_scripts[path] = [source.hash(), script]
	return script


static func resolve_access_path(access_path:String, ctx=null):
	if access_path.is_empty():
		return null
	var parsed = parse_script_target(access_path)
	var base:Script
	if parsed.is_file or parsed.base.contains("/") or parsed.base.is_absolute_path():
		var path:String = parsed.base
		if not path.is_absolute_path() and ctx != null:
			path = ctx.cwd.path_join(path).simplify_path()
		base = _load_script(path)
	else:
		base = UClassDetail.get_global_class_script(parsed.base)
	if not parsed.has_members:
		return base
	return resolve_members(base, parsed.members) if not parsed.members.is_empty() else null


## Read constants only: member traversal never evaluates expressions or instantiates scripts.
static func script_constants(script:Script) -> Dictionary:
	var constants = {}
	while script != null:
		constants.merge(script.get_script_constant_map())
		script = script.get_base_script()
	return constants


static func resolve_members(base:Script, members:String):
	var target = base
	if members.is_empty():
		return target
	for member in members.split(".", true):
		if target == null or member.is_empty():
			return null
		var value = script_constants(target).get(member)
		if not value is Script:
			return null
		target = value
	return target


## prefix includes the selector and any completed member segments, preserving insertion text.
static func complete_members(base:Script, members:String, prefix:String) -> Dictionary:
	var dot = members.rfind(".")
	if dot == 0:
		return {} # A second dot before any member is an invalid chain, not a fresh selector.
	var parent = base if dot < 0 else resolve_members(base, members.left(dot))
	var partial = members if dot < 0 else members.substr(dot + 1)
	var insert_prefix = prefix + ("" if dot < 0 else members.left(dot + 1))
	var options = Options.new()
	if parent == null:
		return options.get_options()
	var constants = script_constants(parent)
	for name in constants:
		if constants[name] is Script and str(name).begins_with(partial):
			options.add_option(str(name), {&"insert": insert_prefix + str(name), &"trailing_char": ""})
	return options.get_options()


static func complete_access_path(text:String, ctx) -> Dictionary:
	var parsed = parse_script_target(text)
	if not parsed.has_members:
		return {}
	return complete_members(resolve_access_path(parsed.base, ctx), parsed.members, parsed.base + ".")


static func target_error(ctx) -> String:
	return ctx.data.get("script_error", "Could not get target.")


static func get_script_from_ctx(ctx):
	return ctx.data.get("script")


## Routing sets exactly one target; no fallback to a stale target from another command.
static func get_target(ctx):
	return ctx.data.get("node") if ctx.data.has("node") else ctx.data.get("script")


static func get_methods_from_ctx(ctx, show_private:bool, static_only:=false,
		inherited:=false, engine:=false):
	var target = get_target(ctx)
	var options = Options.new()
	var methods = get_members(target, "methods", show_private, inherited, engine)
	for name in methods:
		var method = methods[name]
		if static_only and target is Script and not (method.get("flags", 0) & METHOD_FLAG_STATIC):
			continue
		var count = -1 if method.get("flags", 0) & METHOD_FLAG_VARARG else method.get("args", []).size()
		options.add_option(name, {&"metadata": {Options.Keys.ARG_COUNT: count}})
	return options.get_options()


static func get_method_info(target, name:String, inherited:=false, engine:=false) -> Dictionary:
	return get_members(target, "methods", true, inherited, engine).get(name, {})


## The default is the target's own script; --inherited adds base scripts and --engine
## adds the native surface. Instances supply live metadata, including dynamic properties.
static func get_members(target, kind:String, show_private:=false, inherited:=false, engine:=false) -> Dictionary:
	if not is_instance_valid(target):
		return {}
	var script = target if target is Script else target.get_script()
	var members = _script_members(script, kind, inherited or engine) if script != null else {}
	if engine:
		var base_type = script.get_instance_base_type() if target is Script else target.get_class()
		var hint = {"methods": "method", "properties": "property", "signals": "signal",
				"constants": "const", "enums": "enum"}.get(kind, "")
		# Keep the nearest script declaration when it overrides an engine member.
		members.merge(UClassDetail.get_members_of_base_type(base_type, [hint]))
	if target is Node:
		var live:Array = []
		match kind:
			"methods": live = target.get_method_list()
			"signals": live = target.get_signal_list()
			"properties": live = target.get_property_list()
		for info in live:
			var name = str(info.get("name", ""))
			# Property metadata can be supplied dynamically by the instance. Method metadata
			# above already preserves derived overrides, unlike the duplicate live entries.
			if kind == "properties" and (engine or members.has(name)):
				members[name] = info
			elif engine and not members.has(name):
				members[name] = info
	for name in members.keys():
		if name.is_empty() or (not show_private and name.begins_with("_")):
			members.erase(name)
		elif kind == "properties" and members[name].get("usage", 0) & (
				PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_INTERNAL):
			members.erase(name)
	return members


static func _script_members(script:Script, kind:String, inherited:bool) -> Dictionary:
	var members = {}
	if kind == "constants" or kind == "enums":
		var current = script
		while current != null:
			members.merge(current.get_script_constant_map())
			current = current.get_base_script() if inherited else null
		if kind == "enums":
			for name in members.keys():
				if not members[name] is Dictionary or not UClassDetail.check_dict_is_enum(members[name]):
					members.erase(name)
		return members
	var getter = {"methods": "get_script_method_list", "signals": "get_script_signal_list",
			"properties": "get_script_property_list"}.get(kind, "")
	if getter.is_empty():
		return members
	var entries:Array = script.call(getter)
	var base = script.get_base_script()
	if not inherited and base != null:
		# GDScript appends the complete base list after its own declarations (including
		# overrides). Remove that suffix before indexing, without relying on source code
		# or editor-only metadata, so this also works in binary exports.
		var base_entries:Array = base.call(getter)
		entries.resize(entries.size() - base_entries.size())
	for entry in entries:
		var name = str(entry.get("name", ""))
		if not members.has(name):
			members[name] = entry # Derived declarations precede their inherited counterparts.
	return members

