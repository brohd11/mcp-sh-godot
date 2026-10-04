@tool
extends RefCounted
## Runs host commands for the bridge. When editor_console is enabled, commands run with its
## commands, its configured context (undo session, aliases, .gdrc) and its serial queue, so
## agent requests take turns with console input. Otherwise they run in a plain gdsh context.
## Neither gdsh nor editor_console is referenced at parse time, so the addon still loads
## without them and says what is missing.

const GDSH_PATH = "res://addons/addon_lib/gdsh/_ns/gd_sh.gd"
const GDSH_LIB_TREE = "res://addons/addon_lib/gdsh_lib/tree/tree.gd"
const GDSH_LIB_UTILS = "res://addons/addon_lib/gdsh_lib/utils"
const GDSH_MISSING = "gdsh is not installed in this project (res://addons/addon_lib/gdsh). Install it with: gdaddon install brohd11/godot-gdsh"
const EDITOR_CONSOLE_CLASS = "EditorConsoleSingleton"
const SCRIPT_KEY = &"script"

var config

var _gdsh:GDScript
var _editor_console_path:String
# Built on first use: config commands, and gdsh's builtins + gdsh_lib for plain mode.
var _config_scopes = null
var _plain_scopes = null
# Plain mode: one compound undo buffer for every request, and a serial queue.
var _undo_session
signal _turn_freed
var _running := false
var _queue:Array[int] = []
var _next_ticket := 0


func _init(bridge_config) -> void:
	config = bridge_config


## The gdsh namespace script (GDSh), or null when gdsh is not installed.
func gdsh() -> GDScript:
	if _gdsh == null and ResourceLoader.exists(GDSH_PATH):
		_gdsh = load(GDSH_PATH)
	return _gdsh


## EditorConsoleSingleton's script while editor_console is enabled and allowed, else null.
func editor_console() -> GDScript:
	if not config.editor_console:
		return null
	if _editor_console_path.is_empty():
		for entry in ProjectSettings.get_global_class_list():
			if entry.get("class") == EDITOR_CONSOLE_CLASS:
				_editor_console_path = entry.get("path", "")
				break
	if _editor_console_path.is_empty() or not ResourceLoader.exists(_editor_console_path):
		return null
	var script = load(_editor_console_path)
	return script if script != null and script.instance_valid() else null


## Every command offered to agent-shell, by name: {name: scope data}.
func get_scopes() -> Dictionary:
	var scopes := {}
	var ec = editor_console()
	if ec != null:
		scopes.merge(ec.get_instance().get_current_scope_data())
	else:
		scopes.merge(_get_plain_scopes())
	scopes.merge(_get_config_scopes(), true)
	for name in scopes.keys():
		if name.begins_with("__") or config.is_excluded(name):
			scopes.erase(name)
	return scopes


## The command instance for an offered top-level name, or null. Only offered names are
## ever run, so a name cannot smuggle in extra syntax.
## Pass `scopes` from get_scopes() when looking up many names.
func get_command(name:String, scopes = null):
	if scopes == null:
		scopes = get_scopes()
	if name.is_empty() or not scopes.has(name):
		return null
	var command = scopes[name].get(SCRIPT_KEY)
	if command is GDScript:
		command = command.new()
	return command if is_instance_of(command, gdsh().CommandBase) else null


## Run a command line once its turn comes, waiting for async commands to finish.
## `stdin` is what the line reads as piped input. Returns {stdout, stderr, exit_code}.
func run(line:String, stdin:String = "") -> Dictionary:
	var sh = gdsh()
	var ec = editor_console()
	var work = func():
		var ctx = _new_ctx(sh, ec)
		ctx.stdin = stdin
		await sh.Execute.execute_command_multiline(line, ctx)
		# Agents don't render BBCode.
		return {
			"stdout": sh.Context.plain_text(ctx.stdout),
			"stderr": sh.Context.plain_text(ctx.stderr),
			"exit_code": ctx.exit_code,
		}
	if ec != null:
		return await ec.run_serialized(work)
	return await _run_serialized(work)


func _new_ctx(sh:GDScript, ec:GDScript):
	var ctx
	if ec != null:
		ctx = sh.Context.new_ctx("godot-shell request", ec.get_main_ctx())
	else:
		ctx = sh.Context.new("godot-shell request")
		ctx.scopes.merge(_get_plain_scopes(), true)
		if _undo_session == null:
			_undo_session = sh.Undo.Session.new()
		ctx.host_data["undo_session"] = _undo_session
		ctx.host_data["undo_redo"] = func(): return EditorInterface.get_editor_undo_redo()
		ctx.host_data["filesystem_changed"] = func(): EditorInterface.get_resource_filesystem().scan()
	ctx.scopes.merge(_get_config_scopes(), true)
	ctx.collect_raw_commands()
	return ctx


func _get_config_scopes() -> Dictionary:
	if _config_scopes == null:
		_config_scopes = {}
		for dir in config.command_dirs:
			if not DirAccess.dir_exists_absolute(dir):
				push_warning("godot-shell: command dir not found: " + dir)
				continue
			_config_scopes.merge(gdsh().Load.load_directory(dir), true)
		for name in config.commands:
			var script = gdsh().Load.load_command(config.commands[name])
			if script != null:
				_config_scopes[name] = {SCRIPT_KEY: script}
	return _config_scopes


func _get_plain_scopes() -> Dictionary:
	if _plain_scopes == null:
		_plain_scopes = gdsh().Load.load_builtins()
		if config.gdsh_lib:
			if DirAccess.dir_exists_absolute(GDSH_LIB_UTILS):
				_plain_scopes.merge(gdsh().Load.load_directory(GDSH_LIB_UTILS), true)
			if ResourceLoader.exists(GDSH_LIB_TREE):
				var tree = gdsh().Load.load_command(GDSH_LIB_TREE)
				if tree != null:
					_plain_scopes[tree.get_command_name()] = {SCRIPT_KEY: tree}
	return _plain_scopes


func _run_serialized(work:Callable):
	var ticket = _next_ticket
	_next_ticket += 1
	_queue.append(ticket)
	while _running or _queue.front() != ticket:
		await _turn_freed
	_queue.pop_front()
	_running = true
	var result = await work.call()
	_running = false
	# Deferred: the finished caller replies before the next turn starts inside this emission.
	_turn_freed.emit.call_deferred()
	return result
