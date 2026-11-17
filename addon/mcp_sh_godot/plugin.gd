@tool
extends EditorPlugin
## Serves gdsh and the editor's commands to mcp-sh-godot over loopback TCP while enabled. Not
## needed with Editor Console, which serves its own (`mcp --start`), so it stays off while that
## runs. Its export bundles every library it uses.

const Bridge = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/mcp_sh_bridge/src/bridge.gd")
const BridgeConfig = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/mcp_sh_bridge/src/bridge_config.gd")
const Host = preload("res://addons/mcp_sh_godot/src/host.gd")
const MENU_RESTART = "Restart mcp-sh-godot Bridge"
const EDITOR_CONSOLE_CLASS = "EditorConsoleSingleton"
const EDITOR_CONSOLE_NOTE = "mcp-sh-godot: Editor Console is running, so this addon is not needed and stays off. Serve with the console's 'mcp --start' (add it to startup commands)."

var _bridge:Bridge
var _config
var _host = null


func _enter_tree() -> void:
	add_tool_menu_item(MENU_RESTART, restart)
	# Deferred so an Editor Console enabled in the same frame has registered first.
	_autostart.call_deferred()


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_RESTART)
	_stop()


func _autostart() -> void:
	var config = BridgeConfig.load_config()
	if config.autostart:
		restart(config)


## Re-read the config and listen again. Also starts the bridge when autostart is off.
func restart(config = null) -> void:
	_stop()
	if _editor_console_running():
		print(EDITOR_CONSOLE_NOTE)
		return
	_config = config if config != null else BridgeConfig.load_config()
	_bridge = Bridge.new()
	_bridge.name = "McpShGodotBridge"
	_bridge.autostart = false
	_config.apply_to(_bridge)
	_bridge.host = _get_host
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
	_host = null


## An Editor Console that can serve the bridge itself is enabled. Installed but disabled
## doesn't count, so this addon still serves then.
func _editor_console_running() -> bool:
	var console = Bridge.global_class_script(EDITOR_CONSOLE_CLASS)
	return console != null and console.instance_valid() and "mcp" in console.get_instance()


# Built on the first request, so a bridge.json edit followed by Restart takes effect.
func _get_host():
	if _host == null:
		_host = Host.build({
			"undo_redo": func(): return EditorInterface.get_editor_undo_redo(),
			"filesystem_changed": func(): EditorInterface.get_resource_filesystem().scan(),
			"host_plugin_id": (get_script() as Script).resource_path.get_base_dir().trim_prefix("res://addons/"),
		}, _config)
	return _host

