@tool
extends Node
## Loopback TCP listener speaking the agent-shell host protocol, so godot-shell can run
## the editor's commands. See github.com/brohd11/agent-shell (host/protocol.go).
##
## Newline-delimited JSON, one request per connection:
##   hello:  -> {name, version, commands: [{name, summary}]}
##   invoke: {cmd, args, stdin} -> {stdout, stderr, exit_code}
##   help:   {cmd} -> {stdout}
## Errors are {"id", "error"}. The shell itself (pipes, loops, grep/jq...) runs in the
## godot-shell binary. The editor only lists its top-level commands and runs one at a time
## with exact args and piped stdin.

const Runner = preload("res://addons/godot_shell/runner.gd")
const PLUGIN_CFG = "res://addons/godot_shell/plugin.cfg"

const _READ_CHUNK := 65536

var runner:Runner

var _server:TCPServer
var _port:int = 0
var _token:String = ""
# each entry: { "peer": StreamPeerTCP, "buf": String }
var _conns:Array = []
# guards against re-entrant _process: a command can pump the main loop (e.g. save_scene's
# progress bar) which re-enters this node's _process while we're mid-handle.
var _handling:bool = false


func _init(bridge_config) -> void:
	runner = Runner.new(bridge_config)
	set_process(false)


## Listen on 127.0.0.1 only. Returns an Error code.
func start(port:int, token:String = "") -> int:
	stop()
	_server = TCPServer.new()
	var err := _server.listen(port, "127.0.0.1")
	if err != OK:
		_server = null
		return err
	_port = port
	_token = token
	set_process(true)
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


static func addon_version() -> String:
	var cfg = ConfigFile.new()
	if cfg.load(PLUGIN_CFG) != OK:
		return "unknown"
	return str(cfg.get_value("plugin", "version", "unknown"))


func _process(_delta:float) -> void:
	if _server == null:
		return
	if _handling:
		return # a command (e.g. save_scene) can pump the main loop and re-enter _process; don't recurse

	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer != null:
			_conns.append({"peer": peer, "buf": ""})

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
				conn.buf += (result[1] as PackedByteArray).get_string_from_utf8()

		var nl := (conn.buf as String).find("\n")
		if nl != -1:
			var line := (conn.buf as String).substr(0, nl)
			conn.buf = (conn.buf as String).substr(nl + 1) # consume before handling so a re-entrant frame can't re-run it
			_handling = true
			_serve(peer, line) # Not awaited: an async command replies in a later frame.
			_handling = false
			continue # one request per connection; _serve drops it after responding

		keep.append(conn)
	_conns = keep


## Reply once the command finishes; requests arriving meanwhile queue behind it.
func _serve(peer:StreamPeerTCP, line:String) -> void:
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


func _handle_request(req:Dictionary) -> Dictionary:
	var id = req.get("id", null)
	if _token != "" and str(req.get("token", "")) != _token:
		return {"id": id, "error": "Unauthorized"}
	if runner.gdsh() == null:
		return {"id": id, "error": Runner.GDSH_MISSING}
	var method := str(req.get("method", ""))
	match method:
		"hello":
			return {
				"id": id,
				"name": "godot",
				"version": "%s, addon %s" % [Engine.get_version_info().get("string", ""), addon_version()],
				"commands": _command_list(),
			}
		"invoke", "help":
			var cmd := str(req.get("cmd", ""))
			var command = runner.get_command(cmd)
			if command == null:
				return {"id": id, "error": "Unknown command: " + cmd}
			if method == "help":
				# gdsh answers --help in CommandBase._route before anything runs.
				var help:Dictionary = await runner.run(cmd + " --help")
				var text := str(help.get("stdout", "")).strip_edges()
				var tree := {}
				_get_scope_commands(command, "", tree, cmd)
				tree.erase(cmd)
				if not tree.is_empty():
					text += "\n\nAll commands under %s:" % cmd
					for path in tree:
						text += "\n  %s: %s" % [path, tree[path]]
				return {"id": id, "stdout": text}
			var args = req.get("args", [])
			if not args is Array:
				return {"id": id, "error": "'args' must be an array"}
			var line := cmd
			for arg in args:
				line += " " + _sh_word(str(arg))
			var out:Dictionary = await runner.run(line, str(req.get("stdin", "")))
			return {
				"id": id,
				"stdout": out.get("stdout", ""),
				"stderr": out.get("stderr", ""),
				"exit_code": out.get("exit_code", 0),
			}
	return {"id": id, "error": "Unknown method: " + method}


## Top-level commands for the hello response: [{name, summary}].
func _command_list() -> Array:
	var commands := []
	var scopes = runner.get_scopes()
	var names = scopes.keys()
	names.sort()
	for name in names:
		var command = runner.get_command(name, scopes)
		if command == null:
			continue
		var help = command.get_help_string()
		commands.append({
			"name": name,
			"summary": help.get_slice("\n", 0) if help is String else "",
		})
	return commands


## Every subcommand path under a command, with its one-line summary, for help.
static func _get_scope_commands(scope, current_path:String, list:Dictionary, registered_name:String = ""):
	var path = current_path + " " + (registered_name if not registered_name.is_empty() else scope.get_command_name())
	path = path.strip_edges()
	var help = scope.get_help_string()
	if help == null or help == "":
		help = "Undocumented or namespace"
	elif help.contains("\n"):
		help = help.get_slice("\n", 0)
	list[path] = help

	var subs = scope.get_commands()
	for s in subs.keys():
		var get_cmd = subs[s].get(&"get_command")
		if get_cmd != null:
			_get_scope_commands(get_cmd.call(), path, list)


const _SAFE_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-"

## Encode one argv entry as exactly one gdsh word. gdsh treats a word that *starts*
## with a quote as literal (never a flag), so the leading safe characters stay bare and
## only the rest is quoted: "-w" stays a flag, "--name=a b" becomes --name='a b', and
## "a;b" can never become two commands.
static func _sh_word(arg:String) -> String:
	if arg.is_empty():
		return "''"
	var i := 0
	while i < arg.length() and _SAFE_CHARS.contains(arg[i]):
		i += 1
	if i == arg.length():
		return arg
	return arg.substr(0, i) + _sh_quote(arg.substr(i))


static func _sh_quote(text:String) -> String:
	return "'" + text.replace("'", "'\"'\"'") + "'"
