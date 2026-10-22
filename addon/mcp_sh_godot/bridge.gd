@tool
extends Node
## Loopback TCP listener speaking the mcp-sh host protocol, so mcp-sh-godot can run gdsh
## commands in the editor or in a running game. See github.com/brohd11/mcp-sh (host/protocol.go).
##
## The editor plugin and a game add it the same way:
##   var bridge = preload("res://addons/mcp_sh_godot/bridge.gd").new()
##   bridge.host = my_console.create_host()   # optional; plain gdsh when left null
##   add_child(bridge)
##
## Newline-delimited JSON, one request per connection:
##   hello:  -> {name, version, commands: [{name, summary}]}
##   invoke: {cmd, args, stdin} -> {stdout, stderr, exit_code}
##   help:   {cmd} -> {stdout}
## Errors are {"id", "error"}. The shell itself (pipes, loops, grep/jq...) runs in the
## mcp-sh-godot binary. Godot only lists its top-level commands and runs one at a time
## with exact args and piped stdin.

const PLUGIN_CFG = "res://addons/mcp_sh_godot/plugin.cfg"
const EDITOR_PORT = 9510
const RUNTIME_PORT = 9511
const GDSH_MISSING = "gdsh is not available: enable Editor Console, or install gdsh (gdaddon install brohd11/godot-gdsh)"

## Not offered to mcp-sh. The agent's bash already provides shell control, so gdsh's session
## builtins would be no-ops or duplicates. grep/head/tail duplicate mcp-sh's regex-capable
## builtins. os and term would hand the agent the OS directly; terminal/clear/hide_log are
## human UI. help and hidden only re-list other commands. cd/pwd and cn/pwn stay: mcp-sh
## hands bash's cd and pwd to them, and the working directory and node carry over.
## Note this is hygiene, not a security boundary: expr, script call and friends can
## still do anything Godot can.
const DEFAULT_EXCLUDE = [
	"[", "true", "false", "echo", "exit", "return", "break", "continue", "shift",
	"new_ctx", "source", "function", "builtins",
	"grep", "head", "tail",
	"os", "term", "terminal", "clear", "hide_log",
	"help", "hidden",
]

const _READ_CHUNK := 65536

## A GDSh.Host, or any object with host_commands(), host_help(name) and host_run(argv, stdin).
## A Callable returning one is resolved per request. Null: default_host() when listening starts.
var host = null
## 0: 9510 in the editor, 9511 in a running game. -1: any free port; get_port() says which.
@export var port:int = 0
@export var token:String = ""
## Listen once added to the tree. Otherwise call start().
@export var autostart:bool = true
## Listen in release builds too. Off by default: commands can run arbitrary code.
@export var serve_in_release:bool = false
## Names never offered, and names taken back out of exclude.
@export var exclude:PackedStringArray = PackedStringArray(DEFAULT_EXCLUDE)
@export var include:PackedStringArray = []
## Listener bounds, so one misbehaving client can't tie up the main thread. A request line longer
## than max_request_bytes gets a "Request too large" error. A connection that hasn't sent a
## complete line idle_timeout_ms after connecting is dropped (a command that is already running
## isn't timed). Past max_connections, counting those waiting and those being served, new
## connections are closed at once.
@export var max_request_bytes:int = 1048576
@export var max_connections:int = 8
@export var idle_timeout_ms:int = 10000

var _server:TCPServer
var _port:int = 0
# each entry: { "peer": StreamPeerTCP, "buf": PackedByteArray, "since": int (ticks msec) }
var _conns:Array = []
# requests taken off _conns and still awaiting their command
var _in_flight:int = 0
# guards against re-entrant _process: a command can pump the main loop (e.g. save_scene's
# progress bar) which re-enters this node's _process while we're mid-handle.
var _handling:bool = false


func _init() -> void:
	set_process(false)


func _ready() -> void:
	if autostart and not _in_edited_scene():
		start()


func _exit_tree() -> void:
	stop()


## "editor" in the editor, "runtime" in a running game or app.
static func state() -> String:
	return "editor" if Engine.is_editor_hint() else "runtime"


## Listen on 127.0.0.1 only. Returns an Error code; failures are also pushed as errors.
func start() -> int:
	stop()
	if not Engine.is_editor_hint() and not OS.is_debug_build() and not serve_in_release:
		return ERR_UNAVAILABLE
	if host == null:
		host = default_host()
	var listen_port = port if port > 0 else (0 if port < 0 else (EDITOR_PORT if Engine.is_editor_hint() else RUNTIME_PORT))
	_server = TCPServer.new()
	var err := _server.listen(listen_port, "127.0.0.1")
	if err != OK:
		_server = null
		push_error("mcp-sh-godot: could not listen on 127.0.0.1:%s (%s). Is another editor, game or bridge using the port?" % [listen_port, error_string(err)])
		return err
	_port = _server.get_local_port()
	set_process(true)
	var suffix = " (token required)" if token != "" else ""
	print("mcp-sh-godot bridge %s (%s) listening on 127.0.0.1:%s%s" % [addon_version(), state(), _port, suffix])
	return OK


func stop() -> void:
	set_process(false)
	for conn in _conns:
		var peer:StreamPeerTCP = conn.get("peer")
		if peer != null:
			peer.disconnect_from_host()
	_conns.clear()
	if _server != null:
		_server.stop()
		_server = null
	_port = 0


func is_listening() -> bool:
	return _server != null and _server.is_listening()


func get_port() -> int:
	return _port


func is_excluded(name:String) -> bool:
	return name in exclude and not name in include


static func addon_version() -> String:
	var cfg = ConfigFile.new()
	if cfg.load(PLUGIN_CFG) != OK:
		return "unknown"
	return str(cfg.get_value("plugin", "version", "unknown"))


## Plain gdsh: its builtins, plus gdsh_lib's tree and utils when installed beside it, with
## `host_data` hooks for every request (see GDSh.Host). Null when gdsh is not installed.
static func default_host(host_data:Dictionary = {}, gdsh_lib:bool = true):
	var gdsh = global_class_script("GDSh")
	if gdsh == null:
		return null
	var new_host = gdsh.Host.new({"host_data": host_data})
	if gdsh_lib:
		# gd_sh.gd -> _ns -> gdsh -> the library folder that also holds gdsh_lib.
		var lib = gdsh.resource_path.get_base_dir().get_base_dir().get_base_dir().path_join("gdsh_lib")
		if DirAccess.dir_exists_absolute(lib.path_join("utils/src")):
			new_host.add_command_dir(lib.path_join("utils/src"))
		if ResourceLoader.exists(lib.path_join("tree/src/tree.gd")):
			new_host.add_command(lib.path_join("tree/src/tree.gd"))
	return new_host


## The script registered under a global class_name, or null.
static func global_class_script(class_title:String) -> GDScript:
	for entry in ProjectSettings.get_global_class_list():
		if entry.get("class") == class_title:
			var path = entry.get("path", "")
			if ResourceLoader.exists(path):
				return load(path)
	return null


# A bridge saved in a scene shouldn't serve while that scene is open in the editor.
func _in_edited_scene() -> bool:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return false
	var edited = get_tree().edited_scene_root
	return edited != null and (edited == self or edited.is_ancestor_of(self))


func _get_host():
	return host.call() if host is Callable else host


func _process(_delta:float) -> void:
	if _server == null:
		return
	if _handling:
		return # a command (e.g. save_scene) can pump the main loop and re-enter _process; don't recurse

	var now := Time.get_ticks_msec()
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer == null:
			continue
		if _conns.size() + _in_flight >= max_connections:
			peer.disconnect_from_host()
			continue
		_conns.append({"peer": peer, "buf": PackedByteArray(), "since": now})

	var keep:Array = []
	for conn in _conns:
		var peer:StreamPeerTCP = conn.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue # drop disconnected peers

		var avail := peer.get_available_bytes()
		if avail > 0:
			var result := peer.get_partial_data(min(avail, _READ_CHUNK))
			if result[0] == OK:
				conn.buf.append_array(result[1] as PackedByteArray)

		# Bytes, not text: a read can end inside a multi-byte character.
		var nl := (conn.buf as PackedByteArray).find(10)
		if nl != -1 and nl <= max_request_bytes:
			var line := (conn.buf as PackedByteArray).slice(0, nl).get_string_from_utf8()
			conn.buf = PackedByteArray() # consume before handling so a re-entrant frame can't re-run it
			_handling = true
			_serve(peer, line) # Not awaited: an async command replies in a later frame.
			_handling = false
			continue # one request per connection; _serve drops it after responding

		if (conn.buf as PackedByteArray).size() > max_request_bytes:
			_reject(peer, "Request too large")
			continue
		if now - int(conn.since) > idle_timeout_ms:
			peer.disconnect_from_host()
			continue
		keep.append(conn)
	_conns = keep


func _reject(peer:StreamPeerTCP, message:String) -> void:
	peer.put_data((JSON.stringify({"id": null, "error": message}) + "\n").to_utf8_buffer())
	peer.disconnect_from_host()


## Reply once the command finishes; requests arriving meanwhile queue behind it.
func _serve(peer:StreamPeerTCP, line:String) -> void:
	_in_flight += 1
	var resp := {}
	var json := JSON.new()
	if json.parse(line) != OK or not (json.data is Dictionary):
		resp = {"id": null, "error": "Invalid JSON request"}
	else:
		resp = await _handle_request(json.data)

	var payload := JSON.stringify(resp) + "\n"
	peer.poll() # The client may have given up while the command ran.
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.put_data(payload.to_utf8_buffer())
	peer.disconnect_from_host()
	_in_flight -= 1


func _handle_request(req:Dictionary) -> Dictionary:
	var id = req.get("id", null)
	if token != "" and str(req.get("token", "")) != token:
		return {"id": id, "error": "Unauthorized"}
	var current = _get_host()
	if current == null:
		return {"id": id, "error": GDSH_MISSING}
	var method := str(req.get("method", ""))
	match method:
		"hello":
			return {
				"id": id,
				"name": "godot " + state(),
				"version": "%s, addon %s" % [Engine.get_version_info().get("string", ""), addon_version()],
				"commands": _command_list(current),
			}
		"invoke", "help":
			# Only offered names run; the host rejects names it doesn't have.
			var cmd := str(req.get("cmd", ""))
			if cmd.is_empty() or is_excluded(cmd):
				return {"id": id, "error": "Unknown command: " + cmd}
			if method == "help":
				var text:String = await current.host_help(cmd)
				if text.is_empty():
					return {"id": id, "error": "Unknown command: " + cmd}
				return {"id": id, "stdout": text}
			var args = req.get("args", [])
			if not args is Array:
				return {"id": id, "error": "'args' must be an array"}
			var argv := [cmd]
			for arg in args:
				argv.append(str(arg))
			var out:Dictionary = await current.host_run(argv, str(req.get("stdin", "")))
			return {
				"id": id,
				"stdout": out.get("stdout", ""),
				"stderr": out.get("stderr", ""),
				"exit_code": out.get("exit_code", 0),
			}
	return {"id": id, "error": "Unknown method: " + method}


## Top-level commands for the hello response: [{name, summary}].
func _command_list(current) -> Array:
	var commands := []
	for entry in current.host_commands():
		if not is_excluded(str(entry.get("name", ""))):
			commands.append(entry)
	return commands
