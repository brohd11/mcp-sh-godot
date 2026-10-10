@tool
extends RefCounted
## The bridge's config: built-in defaults, then the user file, then the project file.
##   user:    $MCP_SH_CONFIG_DIR/godot/bridge.json (default ~/.mcp-sh/godot/bridge.json)
##   project: res://.mcp-sh/godot/bridge.json
## These sit beside mcp-sh-godot's own config. Scalars replace earlier layers. `commandDirs`
## and `exclude` add to them. `commands` merges by name.

const Bridge = preload("res://addons/mcp_sh_godot/bridge.gd")
const FILE_NAME = "bridge.json"

const KEYS = ["port", "token", "autostart", "editorConsole", "gdshLib", "commandDirs", "commands", "exclude", "include"]

## 0: the bridge's default for where it runs (9510 in the editor).
var port:int = 0
var token:String = ""
## Start listening when the plugin is enabled. Otherwise use Project > Tools.
var autostart:bool = true
## Expose editor_console's commands, run in its context, when it is enabled.
var editor_console:bool = true
## Without editor_console: expose gdsh_lib's tree and utils commands when installed.
var gdsh_lib:bool = true
## gdsh command directories and single command scripts by name, added to the host.
var command_dirs:PackedStringArray = []
var commands:Dictionary = {}
## Names never offered (the bridge's defaults plus these), and names taken back out.
var exclude:PackedStringArray = PackedStringArray(Bridge.DEFAULT_EXCLUDE)
var include:PackedStringArray = []
## Files that were read, in order, for the startup message.
var sources:PackedStringArray = []


static func load_config():
	var cfg = new()
	var env_port = OS.get_environment("MCP_SH_GODOT_PORT")
	if env_port.is_valid_int():
		cfg.port = env_port.to_int()
	cfg.token = OS.get_environment("MCP_SH_GODOT_TOKEN")
	for path in [user_path(), project_path()]:
		cfg._apply_file(path)
	return cfg


static func config_dir() -> String:
	var dir = OS.get_environment("MCP_SH_CONFIG_DIR")
	if dir.is_empty():
		dir = _home().path_join(".mcp-sh")
	return dir


static func user_path() -> String:
	return config_dir().path_join("godot").path_join(FILE_NAME)


static func project_path() -> String:
	return "res://.mcp-sh/godot".path_join(FILE_NAME)


func _apply_file(path:String) -> void:
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_warning("mcp-sh-godot: %s is not a JSON object, ignored" % path)
		return
	sources.append(path)
	var base = path.get_base_dir()
	for key in data:
		if not key in KEYS:
			push_warning("mcp-sh-godot: %s: unknown key '%s'" % [path, key])
	if data.has("port"):
		port = int(data.port)
	if data.has("token"):
		token = str(data.token)
	if data.has("autostart"):
		autostart = bool(data.autostart)
	if data.has("editorConsole"):
		editor_console = bool(data.editorConsole)
	if data.has("gdshLib"):
		gdsh_lib = bool(data.gdshLib)
	for dir in data.get("commandDirs", []):
		command_dirs.append(_resolve(str(dir), base))
	var cmds = data.get("commands", {})
	if cmds is Dictionary:
		for name in cmds:
			commands[name] = _resolve(str(cmds[name]), base)
	for name in data.get("exclude", []):
		exclude.append(str(name))
	for name in data.get("include", []):
		include.append(str(name))


## res:// and absolute paths stay as they are. ~/ is the home folder. Any other path is
## relative to the config file's folder, as in mcp-sh-godot's config.
static func _resolve(path:String, base:String) -> String:
	if path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path():
		return path
	if path == "~" or path.begins_with("~/"):
		return _home().path_join(path.substr(2))
	return base.path_join(path).simplify_path()


static func _home() -> String:
	var home = OS.get_environment("HOME")
	if home.is_empty():
		home = OS.get_environment("USERPROFILE")
	return home
