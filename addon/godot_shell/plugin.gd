@tool
extends EditorPlugin
## Serves the editor's commands to godot-shell over loopback TCP while enabled.

const Bridge = preload("res://addons/godot_shell/bridge.gd")
const BridgeConfig = preload("res://addons/godot_shell/bridge_config.gd")
const MENU_RESTART = "Restart godot-shell Bridge"

var _bridge:Bridge


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
	if config == null:
		config = BridgeConfig.load_config()
	_bridge = Bridge.new(config)
	_bridge.name = "GodotShellBridge"
	add_child(_bridge)
	var err = _bridge.start(config.port, config.token)
	if err != OK:
		push_error("godot-shell: could not listen on 127.0.0.1:%s (%s). Is another editor or bridge using the port?" % [config.port, error_string(err)])
		_stop()
		return
	var suffix = " (token required)" if config.token != "" else ""
	var sources = "" if config.sources.is_empty() else ", config: " + ", ".join(config.sources)
	print("godot-shell bridge %s listening on 127.0.0.1:%s%s%s" % [Bridge.addon_version(), config.port, suffix, sources])


func _stop() -> void:
	if is_instance_valid(_bridge):
		_bridge.stop()
		_bridge.queue_free()
	_bridge = null
