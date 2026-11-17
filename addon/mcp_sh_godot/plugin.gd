@tool
extends EditorPlugin
## Serves plain gdsh (plus gdsh_lib and bridge.json commands) to mcp-sh-godot over loopback TCP
## while enabled. The listener is the mcp_sh_bridge package. Not needed with Editor Console,
## which serves its own commands (`mcp --start`), so it disables itself when that is running.

const BRIDGE_LIB = "res://addons/_lib/mcp_sh_bridge/src" #! gdp-dependency
const BRIDGE_INSTALL = "gdaddon install brohd11/godot-mcp-sh-bridge"
const MENU_RESTART = "Restart mcp-sh-godot Bridge"
const EDITOR_CONSOLE_CLASS = "EditorConsoleSingleton"
const EDITOR_CONSOLE_NOTE = "mcp-sh-godot: Editor Console is running, so this addon is not needed and stays off. Serve with the console's 'mcp --start' (add it to startup commands)."

# Loaded, not preloaded, so a missing package is a clear message rather than a parse error.
var Bridge:GDScript
var BridgeConfig:GDScript
var _bridge:Node
var _config
var _host = null


func _enter_tree() -> void:
	add_tool_menu_item(MENU_RESTART, restart)
	if not ResourceLoader.exists(BRIDGE_LIB.path_join("bridge.gd")):
		push_error("mcp-sh-godot: the mcp_sh_bridge package is missing (res://addons/_lib/mcp_sh_bridge). Install it: " + BRIDGE_INSTALL)
		return
	Bridge = load(BRIDGE_LIB.path_join("bridge.gd"))
	BridgeConfig = load(BRIDGE_LIB.path_join("bridge_config.gd"))
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
	if Bridge == null:
		push_error("mcp-sh-godot: the mcp_sh_bridge package is missing. Install it: " + BRIDGE_INSTALL)
		return
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
	return console != null and _has_method(console, "start_mcp_sh_bridge") and console.instance_valid()


## Plain gdsh with editor hooks, gdsh_lib's tree and utils, and bridge.json's commands. Built on
## the first request, since gdsh may be installed after this plugin loads.
func _get_host():
	if _host == null:
		_host = Bridge.default_host({
			"undo_redo": func(): return EditorInterface.get_editor_undo_redo(),
			"filesystem_changed": func(): EditorInterface.get_resource_filesystem().scan(),
		})
		if _host != null and _config.gdsh_lib:
			_add_gdsh_lib(_host)
		_config.add_commands_to(_host)
	return _host


func _add_gdsh_lib(host) -> void:
	# gd_sh.gd -> _ns -> gdsh -> the library folder that also holds gdsh_lib.
	var gdsh = Bridge.global_class_script("GDSh")
	var lib = gdsh.resource_path.get_base_dir().get_base_dir().get_base_dir().path_join("gdsh_lib")
	if DirAccess.dir_exists_absolute(lib.path_join("utils/src")):
		host.add_command_dir(lib.path_join("utils/src"))
	if ResourceLoader.exists(lib.path_join("tree/src/tree.gd")):
		host.add_command(lib.path_join("tree/src/tree.gd"))


static func _has_method(script:Script, method:String) -> bool:
	for entry in script.get_script_method_list():
		if entry.get("name") == method:
			return true
	return false
