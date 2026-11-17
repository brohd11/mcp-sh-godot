
extends RefCounted
## Load GDSh.CommandBase scripts without editor configuration or a singleton.

const Paths = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/paths.gd")
const Types = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/types.gd")
const CommandBase = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd")


## Returns null and reports an error for an invalid command.
static func load_command(path:String) -> GDScript:
	if not ResourceLoader.exists(path, "GDScript"):
		push_error("GDSh.Load: command not found: " + path)
		return null
	var script = ResourceLoader.load(path, "GDScript") as GDScript
	# Not can_instantiate(): it is false for non-@tool scripts while scripting is disabled (the editor), and for @abstract ones.
	if script == null:
		push_error("GDSh.Load: cannot instantiate command: " + path)
		return null
	var base = script.get_base_script()
	while base != null and base != CommandBase:
		base = base.get_base_script()
	if base == null:
		push_error("GDSh.Load: command must extend GDSh.CommandBase: " + path)
		return null
	var name = script.get_command_name()
	if not name is String or name.is_empty() or name == "UnamedCommand":
		push_error("GDSh.Load: command has no valid name: " + path)
		return null
	return script

## Commands outside res:// (user command directories) reload on use, so edits apply without a restart.
static func fresh(script:GDScript) -> GDScript:
	if script == null or script.resource_path.is_empty() or script.resource_path.begins_with("res://"):
		return script
	var reloaded = ResourceLoader.load(script.resource_path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as GDScript
	return reloaded if reloaded != null else script

## Loads loose .gd files and name/name.gd entries, without flattening child commands.
## child_directories_only is used by CommandBase to discover its subcommands.
static func load_directory(path:String, child_directories_only:=false) -> Dictionary:
	var candidates: Array[String] = []
	var entries = Paths.list_directory(path)
	for entry in entries:
		if entry.ends_with("/"):
			var name = entry.trim_suffix("/")
			var candidate = path.path_join(name).path_join(name + ".gd")
			if ResourceLoader.exists(candidate, "GDScript"):
				candidates.append(candidate)
		# A loose manifest.gd preloads the directory's commands for exporters; it is not a command.
		elif not child_directories_only and entry.ends_with(".gd") and entry != "manifest.gd":
			candidates.append(path.path_join(entry))
	candidates.sort()
	var scopes = {}
	for candidate in candidates:
		var script = load_command(candidate)
		if script == null:
			continue
		var name = script.get_command_name()
		if scopes.has(name):
			push_error("GDSh.Load: duplicate command '%s', skipping %s" % [name, candidate])
			continue
		scopes[name] = {Types.ScopeDataKeys.SCRIPT: script}
	return scopes

## Untagged on purpose: a command-only export skips the builtins. GDSh.Host preloads the list,
## which ships it and rewrites this path along with it. Inline in load() so it stays absolute.
static func load_builtins() -> Dictionary:
	var script = load("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/builtin_scripts.gd")
	if script == null:
		push_error("GDSh.Load: builtins not exported; reference GDSh.Host to ship them")
		return {}
	return script.load_builtins()

