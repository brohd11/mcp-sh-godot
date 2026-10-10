@tool
extends EditorPlugin
## Serves the editor's commands to mcp-sh-godot over loopback TCP while enabled.

const Bridge = preload("res://addons/mcp_sh_godot/bridge.gd")
const BridgeConfig = preload("res://addons/mcp_sh_godot/bridge_config.gd")
const MENU_RESTART = "Restart mcp-sh-godot Bridge"
const EDITOR_CONSOLE_CLASS = "EditorConsoleSingleton"

var _bridge:Bridge
var _config
var _console_host = null
var _plain_host = null


func _enter_tree() -> void:
	add_tool_menu_item(MENU_RESTART, restart)
	var config = BridgeConfig.load_config()
	if config.autostart:
		restart(config)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_RESTART)
	_stop()


## Re-read the config and listen again. Also starts the bridge when autostart is off.
func restart(config = null) -> void:
	_stop()
	_config = config if config != null else BridgeConfig.load_config()
	_bridge = Bridge.new()
	_bridge.name = "McpShGodotBridge"
	_bridge.host = _resolve_host
	_bridge.port = _config.port
	_bridge.token = _config.token
	_bridge.exclude = _config.exclude
	_bridge.include = _config.include
	_bridge.autostart = false
	add_child(_bridge)
	if _bridge.start() != OK:
		_stop()
		return
	if not _config.sources.is_empty():
		print("mcp-sh-godot bridge config: " + ", ".join(_config.sources))


func _stop() -> void:
	if is_instance_valid(_bridge):
		_bridge.stop()
		_bridge.queue_free()
	_bridge = null
	_console_host = null
	_plain_host = null


## The host for each request: Editor Console's while it runs (unless editorConsole is off),
## else plain gdsh with editor hooks. Resolved per request, since either addon can load or
## unload after this one.
func _resolve_host():
	if _config.editor_console:
		var console = Bridge.global_class_script(EDITOR_CONSOLE_CLASS)
		if console != null and _has_method(console, "create_host") and console.instance_valid():
			if _console_host == null:
				_console_host = _add_config_commands(console.create_host())
			return _console_host
	_console_host = null
	if _plain_host == null:
		_plain_host = _add_config_commands(Bridge.default_host({
			"undo_redo": func(): return EditorInterface.get_editor_undo_redo(),
			"filesystem_changed": func(): EditorInterface.get_resource_filesystem().scan(),
		}, _config.gdsh_lib))
	return _plain_host


func _add_config_commands(host):
	if host == null:
		return null
	for dir in _config.command_dirs:
		host.add_command_dir(dir)
	for name in _config.commands:
		host.add_command(_config.commands[name], name)
	return host


static func _has_method(script:Script, method:String) -> bool:
	for entry in script.get_script_method_list():
		if entry.get("name") == method:
			return true
	return false
