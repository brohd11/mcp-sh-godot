@tool
extends RefCounted
## The bridge's config: built-in defaults, then the user file, then the project file.
##   user:    $MCP_SH_CONFIG_DIR/godot/bridge.json (default ~/.mcp-sh/godot/bridge.json)
##   project: res://.mcp-sh/godot/bridge.json
## These sit beside mcp-sh-godot's own config. Scalars replace earlier layers. `commandDirs`
## and `exclude` add to them. `commands` merges by name.
## Each layer's folder is also a gdsh command root (commands/ + packages/<name>/cmd), read
## before its commandDirs with no config. Only hosts that ask get the roots, with
## add_commands_to(host, true): the editor plugins do; a game's own bridge doesn't. Those hosts
## also get gdsh's shared ~/.gdsh and res://.gdsh roots (GDSh.Load.default_dirs) first.

const Bridge = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/mcp_sh_bridge/src/bridge.gd")
const FILE_NAME = "bridge.json"
## A root's loose-command folder, for gdsh copies without add_command_root.
const COMMANDS_DIR = "commands"

const KEYS = ["port", "token", "autostart", "gdshLib", "commandDirs", "commands", "exclude", "include", "maxRequestBytes", "maxConnections", "idleTimeoutMs", "gdshRoot"]

## 0: the bridge's default for where it runs (9510 in the editor). -1: any free port.
var port:int = 0
var token:String = ""
## The mcp-sh-godot addon's keys; Editor Console starts with `mcp --start` instead.
## Start listening when the plugin is enabled. Otherwise use Project > Tools.
var autostart:bool = true
## Expose gdsh_lib's tree and utils commands when installed.
var gdsh_lib:bool = true
## bridge.json's gdsh command directories and single command scripts by name, added to the host.
var command_dirs:PackedStringArray = []
var commands:Dictionary = {}
## Names never offered (the bridge's defaults plus these), and names taken back out.
var exclude:PackedStringArray = PackedStringArray(Bridge.DEFAULT_EXCLUDE)
var include:PackedStringArray = []
## Listener bounds; see the bridge's exports of the same names.
var max_request_bytes:int = 1048576
var max_connections:int = 8
var idle_timeout_ms:int = 10000
## Files that were read, in order, for the startup message.
var sources:PackedStringArray = []
## Every directory in the order the host gets them: [path, is a layer's command root].
var _dirs:Array = []


static func load_config():
	var cfg = new()
	var env_port = OS.get_environment("MCP_SH_GODOT_PORT")
	if env_port.is_valid_int():
		cfg.port = env_port.to_int()
	cfg.token = OS.get_environment("MCP_SH_GODOT_TOKEN")
	for path in [user_path(), project_path()]:
		# Listed on each request by the host, so it may be created after startup.
		cfg._dirs.append([path.get_base_dir(), true])
		cfg._apply_file(path)
	return cfg


## Copy the listener settings onto a bridge that hasn't started yet.
func apply_to(bridge) -> void:
	bridge.port = port
	bridge.token = token
	bridge.exclude = exclude
	bridge.include = include
	bridge.max_request_bytes = max_request_bytes
	bridge.max_connections = max_connections
	bridge.idle_timeout_ms = idle_timeout_ms


## Add `commandDirs` and `commands` to a GDSh.Host, and with command_roots the gdsh default
## roots and each layer's folder as a root too. Returns the host; null stays null.
func add_commands_to(host, command_roots:=false):
	if host == null:
		return null
	# Before the layers, so bridge.json wins a name clash. Older gdsh copies lack it.
	if command_roots and host.has_method("add_default_dirs"):
		host.add_default_dirs()
	for entry in _dirs:
		if not entry[1]:
			host.add_command_dir(entry[0])
		elif not command_roots:
			continue
		elif host.has_method("add_command_root"):
			host.add_command_root(entry[0])
		elif DirAccess.dir_exists_absolute(entry[0].path_join(COMMANDS_DIR)):
			host.add_command_dir(entry[0].path_join(COMMANDS_DIR))
	for name in commands:
		host.add_command(commands[name], name)
	return host


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
	if data.has("gdshLib"):
		gdsh_lib = bool(data.gdshLib)
	if data.has("maxRequestBytes"):
		max_request_bytes = int(data.maxRequestBytes)
	if data.has("maxConnections"):
		max_connections = int(data.maxConnections)
	if data.has("idleTimeoutMs"):
		idle_timeout_ms = int(data.idleTimeoutMs)
	for dir in data.get("commandDirs", []):
		var resolved = _resolve(str(dir), base)
		command_dirs.append(resolved)
		_dirs.append([resolved, false])
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

