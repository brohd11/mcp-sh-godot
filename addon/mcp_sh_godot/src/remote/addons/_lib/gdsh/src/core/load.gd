
extends RefCounted
## Load GDSh.CommandBase scripts without editor configuration or a singleton.

const Paths = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/paths.gd")
const Types = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/types.gd")
const CommandBase = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd")

const ScriptRebase = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/util_r/src/object/script_rebase.gd")

## A user command's extends line is swapped for this copy's CommandBase when it names any gdsh
## copy's command_base.gd: the plain lib, or one bundled into a plugin.
const _COMMAND_BASE_SUFFIX = "gdsh/src/core/command_base.gd"

## Built user commands by path: [source hash, script or null, why it failed or ""].
static var _user_builds := {}


## User commands live outside res:// (~/.mcp-sh/godot/commands and other folders) or in the
## project's res://.mcp-sh/. They can't know where gdsh is installed, so they are compiled
## against this copy: write `extends "res://addons/_lib/gdsh/src/core/command_base.gd"` and they
## run under any host. They extend command_base.gd directly, reach the library through its
## consts (Context, Options, Utils, ...) and don't override _init. They are rebuilt when the file
## changes, so edits apply without a restart.
static func is_user_path(path:String) -> bool:
	return not path.begins_with("res://") or path.begins_with("res://.mcp-sh/")


## Returns null and reports an error for an invalid command.
static func load_command(path:String) -> GDScript:
	if is_user_path(path):
		return _build_user(path)
	if not ResourceLoader.exists(path, "GDScript"):
		push_error("GDSh.Load: command not found: " + path)
		return null
	var script = ResourceLoader.load(path, "GDScript") as GDScript
	# Not can_instantiate(): it is false for non-@tool scripts while scripting is disabled (the editor), and for @abstract ones.
	if script == null:
		push_error("GDSh.Load: cannot instantiate command: " + path)
		return null
	var problem = _check_command(script)
	if not problem.is_empty():
		push_error("GDSh.Load: %s: %s" % [problem, path])
		return null
	return script


## Why script can't be a command, or "".
static func _check_command(script:GDScript) -> String:
	var base = script.get_base_script()
	while base != null and base != CommandBase:
		base = base.get_base_script()
	if base == null:
		return "command must extend GDSh.CommandBase"
	var name = script.get_command_name()
	if not name is String or name.is_empty() or name == "UnamedCommand":
		return "command has no valid name"
	return ""

## User commands are rebuilt on use when their file changed, so edits apply without a restart.
## A file that no longer builds keeps its last good script (the error is printed once).
static func fresh(script:GDScript) -> GDScript:
	if script == null or script.resource_path.is_empty() or not is_user_path(script.resource_path):
		return script
	var rebuilt = _build_user(script.resource_path)
	return rebuilt if rebuilt != null else script


## Built and checked once per version of the file. A failure is remembered too, with its
## reason, so a broken file reports once rather than on every listing, and hosts can show why.
static func _build_user(path:String) -> GDScript:
	if not FileAccess.file_exists(path):
		push_error("GDSh.Load: command not found: " + path)
		return null
	var source_hash = FileAccess.get_file_as_string(path).hash()
	var built = _user_builds.get(path)
	if built != null and built[0] == source_hash:
		return built[1]
	var error = ""
	var script = ScriptRebase.build(path, CommandBase, _COMMAND_BASE_SUFFIX)
	if script == null:
		error = "\n".join(ScriptRebase.last_errors)
		if error.is_empty():
			error = "it failed to compile; the error is in Godot's Output"
	else:
		error = _check_command(script)
		if error == "command must extend GDSh.CommandBase":
			error = "it must extend \"res://addons/_lib/gdsh/src/core/command_base.gd\" directly"
	if not error.is_empty():
		push_error("GDSh.Load: cannot load command %s: %s" % [path, error])
		script = null
	_user_builds[path] = [source_hash, script, error]
	return script


## Failed user commands under dir, as {path: reason}. Only files still there are listed; the
## reason is a parse error's "file:line: message" lines when Godot can report them (4.5+).
static func user_build_errors(dir:String) -> Dictionary:
	var prefix = dir.trim_suffix("/") + "/"
	var errors = {}
	for path in _user_builds:
		var built = _user_builds[path]
		if built[1] == null and path.begins_with(prefix) and FileAccess.file_exists(path):
			errors[path] = built[2]
	return errors

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

