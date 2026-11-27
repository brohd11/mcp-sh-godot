extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"
## Addon plugin state. In the editor it goes through EditorInterface, fetched by name so the file
## also compiles without the editor API; on the gdsh CLI it edits editor_plugins/enabled directly.
## The interactive list lives in src/ and is load()ed only when a TUI host asks for it, so the CLI
## bundle (which ships cmd/settings) doesn't pull in the TUI library.

const _SETTING = "editor_plugins/enabled"
## Anchors the TUI's path (a subclass's own script may live anywhere); from cmd/settings. The editor
## manifest preloads the TUI so host exports still ship it.
const _Settings = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/editor/cmd/settings/settings.gd")
const _TUI = "../../src/plugin_tui.gd"

const _HELP = \
"List addon plugins, or enable/disable them.
Usage: settings plugin [<id>...] [--list | --enable | --disable | --reload]
  (no args)   the interactive list in Editor Console, else the plain list (--list forces it)
  <id>...     print each addon's state (ids are folders under res://addons with a plugin.cfg)
  --enable / --disable   change it; already in that state is not an error
  --reload    disable then enable (editor only)
In the editor the plugin is loaded/unloaded at once. On the gdsh CLI this edits project.godot,
so it applies when the editor next opens the project: don't run it while the editor has it open."

var list_flag := false
var enable_flag := false
var disable_flag := false
var reload_flag := false
## The interactive list while it runs.
var _tui


static func get_command_name() -> String:
	return "plugin"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:0",
	})


func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--list", {&"help": "Print the plain list, even where the interactive one is available."})
	options.add_option("--enable", {&"help": "Enable the given plugins."})
	options.add_option("--disable", {&"help": "Disable the given plugins."})
	options.add_option("--reload", {&"help": "Disable then enable the given plugins (editor only)."})
	return options.get_options()


func _get_completions(completion:Completion):
	var options = Options.new()
	options.merge(_get_flags())
	for plugin in _list_plugins():
		if not plugin.id in positional_args:
			options.add_option(plugin.id)
	return options.get_options()


func _execute(ctx:Context):
	if int(enable_flag) + int(disable_flag) + int(reload_flag) + int(list_flag) > 1:
		ctx.append_error("Pass at most one of --list, --enable, --disable, --reload.")
		return ExitCode.ERR
	var editor = _editor()
	if editor == null and _host() != Host.CLI:
		ctx.append_error("settings plugin: needs the editor or the gdsh CLI")
		return ExitCode.FAIL
	if positional_args.is_empty():
		if enable_flag or disable_flag or reload_flag:
			ctx.append_error("Name the plugins to change.")
			return ExitCode.ERR
		if not list_flag and editor != null and _tui_available(ctx):
			return await _run_tui(ctx)
		for plugin in _list_plugins():
			ctx.append_output(_state_line(plugin))
		return ExitCode.OK

	var plugins = {}
	for plugin in _list_plugins():
		plugins[plugin.id] = plugin
	for id in positional_args:
		if not plugins.has(id):
			ctx.append_error("No addon plugin: %s (no %s)" % [id, _cfg_path(id)])
			return ExitCode.ERR
		if not plugins[id].error.is_empty() and (enable_flag or reload_flag):
			ctx.append_error(plugins[id].error)
			return ExitCode.ERR
	if not (enable_flag or disable_flag or reload_flag):
		for id in positional_args:
			ctx.append_output(_state_line(plugins[id]))
		return ExitCode.OK
	if reload_flag and editor == null:
		ctx.append_error("--reload needs the editor.")
		return ExitCode.ERR
	var host_id = _host_plugin_id() if editor != null else ""
	if (disable_flag or reload_flag) and host_id in positional_args:
		ctx.append_error("%s hosts this command and can't disable itself." % host_id)
		return ExitCode.ERR

	var changed = false
	for id in positional_args:
		if reload_flag:
			_set_enabled(id, false)
			_set_enabled(id, true)
			ctx.append_output("Reloaded " + id)
			continue
		var target = enable_flag
		if _is_enabled(id) == target:
			ctx.append_output("%s already %s" % [id, "enabled" if target else "disabled"])
			continue
		_set_enabled(id, target)
		changed = true
		ctx.append_output(("Enabled " if target else "Disabled ") + id)
	if changed and editor == null:
		var err = _save()
		if err != OK:
			ctx.append_error("project.godot save failed (%s)." % error_string(err))
			return ExitCode.FAIL
	return ExitCode.OK


func _state_line(plugin:Dictionary) -> String:
	if not plugin.error.is_empty():
		return "invalid  %s: %s" % [plugin.id, plugin.error]
	return "%-8s %s" % ["enabled" if _is_enabled(plugin.id) else "disabled", plugin.id]


func _tui_available(ctx:Context) -> bool:
	var begin = ctx.host_data.get("tui_begin")
	return begin is Callable and begin.is_valid() and ResourceLoader.exists(_tui_path())


func _run_tui(ctx:Context) -> int:
	_tui = load(_tui_path()).new()
	_tui.backend = self
	_tui._initialize(ctx)
	var status = await _tui.run()
	_tui = null
	return status


func _tui_path() -> String:
	var anchor:Script = _Settings
	return anchor.resource_path.get_base_dir().path_join(_TUI).simplify_path()


# Seams: the tests and the TUI go through these.

## EditorInterface, or null outside the editor (the CLI runs the editor binary with --script).
func _editor() -> Object:
	if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		return Engine.get_singleton("EditorInterface")
	return null


func _addons_path() -> String:
	return "res://addons"


func _cfg_path(id:String) -> String:
	return _addons_path().path_join(id).path_join("plugin.cfg")


## Folders under the addons path with a plugin.cfg: {id, name, error}; error is "" when usable.
func _list_plugins() -> Array[Dictionary]:
	var plugins:Array[Dictionary] = []
	var ids = Array(DirAccess.get_directories_at(_addons_path()))
	ids.sort()
	for id in ids:
		var directory = _addons_path().path_join(id)
		var path = directory.path_join("plugin.cfg")
		if not FileAccess.file_exists(path):
			continue
		var config = ConfigFile.new()
		var error = config.load(path)
		var name = str(config.get_value("plugin", "name", id)) if error == OK else id
		var script = str(config.get_value("plugin", "script", "")) if error == OK else ""
		var issue = "Cannot read plugin.cfg: " + id if error != OK else ""
		if issue.is_empty() and (script.is_empty() or not FileAccess.file_exists(directory.path_join(script))):
			issue = "Missing plugin script: " + id
		plugins.append({"id": id, "name": name if not name.is_empty() else id, "error": issue})
	return plugins


## The addon that hosts the commands, which can't be disabled from them. A host names itself
## through host_data; otherwise walk up from this script, which finds the plugin bundling it.
func _host_plugin_id() -> String:
	var hooked = str(_ctx_obj.host_data.get("host_plugin_id", "")) if _ctx_obj != null else ""
	if not hooked.is_empty():
		return hooked
	var directory = (get_script() as Script).resource_path.get_base_dir()
	while directory.begins_with("res://addons/"):
		if FileAccess.file_exists(directory.path_join("plugin.cfg")):
			return directory.trim_prefix("res://addons/")
		directory = directory.get_base_dir()
	return ""


func _is_enabled(id:String) -> bool:
	var editor = _editor()
	if editor != null:
		return editor.is_plugin_enabled(id)
	return _cfg_path(id) in ProjectSettings.get_setting(_SETTING, PackedStringArray())


## Headless, this only sets the value; _execute saves once after all changes.
func _set_enabled(id:String, enabled:bool) -> void:
	var editor = _editor()
	if editor != null:
		editor.set_plugin_enabled(id, enabled)
		return
	var list:PackedStringArray = ProjectSettings.get_setting(_SETTING, PackedStringArray())
	var path = _cfg_path(id)
	if enabled and not path in list:
		list.append(path)
	elif not enabled and path in list:
		list.remove_at(list.find(path))
	ProjectSettings.set_setting(_SETTING, list)


func _save() -> int:
	return ProjectSettings.save()

