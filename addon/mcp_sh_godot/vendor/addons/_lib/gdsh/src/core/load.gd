
extends RefCounted
## Load GDSh.CommandBase scripts without editor configuration or a singleton.

const Paths = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/paths.gd")
const Types = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/types.gd")
const CommandBase = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd")
const _Anchor = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/anchor.gd")

const ScriptRebase = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/util_r/src/object/script_rebase.gd")

## A user command's extends line is swapped for this copy's CommandBase when it names any gdsh
## copy's command_base.gd: the plain lib, or one bundled into a plugin. Any command whose direct
## base is another copy's command_base.gd (a plugin that ships gdsh) is rebuilt the same way.
const _COMMAND_BASE_SUFFIX = "gdsh/src/core/command_base.gd"
const PLUGINS_DIR = "res://addons/"

## Built user commands by path: [source hash, script or null, why it failed or ""].
static var _user_builds := {}


## User commands live outside res:// (~/.gdsh, ~/.mcp-sh/godot and other folders) or in the
## project's res://.gdsh/ or res://.mcp-sh/. They can't know where gdsh is installed, so
## they are compiled against this copy: write
## `extends "res://addons/_lib/gdsh/src/core/command_base.gd"` and they run under any host. They extend command_base.gd directly, reach the library through its
## consts (Context, Options, Utils, ...) and don't override _init. They are rebuilt when the file
## changes, so edits apply without a restart.
## This copy's own files never are, even when it runs from outside res:// (the CLI).
static func is_user_path(path:String) -> bool:
	if path.begins_with(_Anchor.root()):
		return false
	return not path.begins_with("res://") or path.begins_with("res://.gdsh/") or path.begins_with("res://.mcp-sh/") \
		or _in_ignored_plugin_cmd(path)


## A released plugin's cmd/ may be .gdignore'd so the editor never parses it (its gdsh may be
## absent); those commands are compiled against this copy, like ~/.gdsh ones.
static func _in_ignored_plugin_cmd(path:String) -> bool:
	if not path.begins_with(PLUGINS_DIR):
		return false
	var parts = path.trim_prefix(PLUGINS_DIR).split("/")
	return parts.size() > 2 and parts[1] == "cmd" \
		and FileAccess.file_exists(PLUGINS_DIR.path_join(parts[0]).path_join("cmd/.gdignore"))


## The shared user folder: $GDSH_HOME, else ~/.gdsh ("" without a home folder).
static func home_dir() -> String:
	var dir = OS.get_environment("GDSH_HOME")
	if not dir.is_empty():
		return dir
	var home = OS.get_environment("HOME")
	if home.is_empty():
		home = OS.get_environment("USERPROFILE")
	return "" if home.is_empty() else home.path_join(".gdsh")


## Every host's no-config command dirs, in load order (later wins): enabled plugins' cmd/, then
## root_dirs of the user folder, then of res://.gdsh. Dot folders are never scanned by the editor,
## and these are user paths, so they need no gdsh install. Listed fresh each call.
static func default_dirs() -> PackedStringArray:
	var dirs := plugin_dirs()
	for root in [home_dir(), "res://.gdsh"]:
		if not root.is_empty():
			dirs.append_array(root_dirs(root))
	return dirs


## The cmd/ dirs of enabled top-level plugins (res://addons/<name>/), sorted. Read from the
## project's enabled list rather than the editor, so the editor, MCP and the headless CLI agree.
## `enabled` (plugin.cfg paths) defaults to editor_plugins/enabled.
static func plugin_dirs(enabled = null) -> PackedStringArray:
	if enabled == null:
		enabled = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	var dirs := PackedStringArray()
	for cfg in enabled:
		var dir = str(cfg).get_base_dir()
		if dir.get_base_dir() + "/" != PLUGINS_DIR:
			continue
		var cmd = dir.path_join("cmd")
		if DirAccess.dir_exists_absolute(cmd):
			dirs.append(cmd)
	dirs.sort()
	return dirs


## A command root's dirs, in load order: its commands/, then each packages/<name>/cmd (sorted).
## Missing parts are skipped. Listed fresh each call.
static func root_dirs(root:String) -> PackedStringArray:
	var dirs := PackedStringArray()
	var commands = root.path_join("commands")
	if DirAccess.dir_exists_absolute(commands):
		dirs.append(commands)
	var packages = root.path_join("packages")
	if not DirAccess.dir_exists_absolute(packages):
		return dirs
	var names = Array(DirAccess.get_directories_at(packages))
	names.sort()
	for name in names:
		var cmd = packages.path_join(name).path_join("cmd")
		if DirAccess.dir_exists_absolute(cmd):
			dirs.append(cmd)
	return dirs


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
	if not problem.is_empty() and _extends_other_copy(script):
		return _build_user(path, true)
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

## The direct base is another gdsh copy's CommandBase, e.g. one bundled into a released plugin.
## Direct only: the rebase swaps just the file's own extends line.
static func _extends_other_copy(script:GDScript) -> bool:
	var base = script.get_base_script()
	return base != null and base != CommandBase and base.resource_path.ends_with(_COMMAND_BASE_SUFFIX)

## User commands are rebuilt on use when their file changed, so edits apply without a restart.
## A file that no longer builds keeps its last good script (the error is printed once).
static func fresh(script:GDScript) -> GDScript:
	if script == null or script.resource_path.is_empty() or not is_user_path(script.resource_path):
		return script
	var rebuilt = _build_user(script.resource_path)
	return rebuilt if rebuilt != null else script


## Built and checked once per version of the file. A failure is remembered too, with its
## reason, so a broken file reports once rather than on every listing, and hosts can show why.
## swap_any: the base is already known to be a gdsh copy, so swap whatever form the extends takes
## (an exporter may have written a uid:// or relative path).
static func _build_user(path:String, swap_any := false) -> GDScript:
	if not FileAccess.file_exists(path):
		push_error("GDSh.Load: command not found: " + path)
		return null
	var source_hash = FileAccess.get_file_as_string(path).hash()
	var built = _user_builds.get(path)
	if built != null and built[0] == source_hash:
		return built[1]
	var error = ""
	var script = ScriptRebase.build(path, CommandBase, "" if swap_any else _COMMAND_BASE_SUFFIX)
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
	# User files are read from disk; an ignored dir has nothing in the resource index.
	var user = is_user_path(path.path_join("_"))
	for entry in entries:
		if entry.ends_with("/"):
			var name = entry.trim_suffix("/")
			var candidate = path.path_join(name).path_join(name + ".gd")
			if FileAccess.file_exists(candidate) if user else ResourceLoader.exists(candidate, "GDScript"):
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

## A command package keeps its commands in <path>/cmd/ (a manifest.gd plus command dirs), so
## any package registers the same way. Returns {} and reports an error when cmd/ is missing.
static func load_package(path:String) -> Dictionary:
	var dir = path.path_join("cmd")
	if not DirAccess.dir_exists_absolute(dir):
		push_error("GDSh.Load: package has no cmd/ dir: " + path)
		return {}
	return load_directory(dir)

## Untagged on purpose: a command-only export skips the builtins. GDSh.Host preloads the list,
## which ships it.
static func load_builtins() -> Dictionary:
	var script = load(_Anchor.path("src/core/builtin_scripts.gd"))
	if script == null:
		push_error("GDSh.Load: builtins not exported; reference GDSh.Host to ship them")
		return {}
	return script.load_builtins()

