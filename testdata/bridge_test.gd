extends SceneTree
## Headless tests for bridge.gd's listener, run by bridge_test.go in a throwaway project:
##   godot --headless --path PROJECT -s res://bridge_test.gd
## Prints "ok NAME" / "FAIL NAME: why" per test and exits 1 on any failure.

const Bridge = preload("res://addons/mcp_sh_godot/bridge.gd")
const BridgeConfig = preload("res://addons/mcp_sh_godot/bridge_config.gd")

var bridge: Node
var failures := 0


## A host with one command, say (echo is excluded by default), which returns its arguments and stdin.
class FakeHost:
	extends RefCounted

	func host_commands() -> Array:
		return [{"name": "say", "summary": "print args and stdin"}]

	func host_help(name: String) -> String:
		return "say ARGS..." if name == "say" else ""

	func host_run(argv: Array, stdin: String = "") -> Dictionary:
		return {"stdout": " ".join(argv.slice(1)) + stdin, "stderr": "", "exit_code": 0}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for test in ["test_hello_and_invoke", "test_wrong_token", "test_free_port", "test_split_utf8",
			"test_oversized_request", "test_idle_connection", "test_connection_flood", "test_config_keys"]:
		_start_bridge()
		# Test functions are untyped so a script error inside one returns null, not "".
		var result: Variant = await call(test)
		var problem: String = result if result is String else "script error (see the log above)"
		print(("ok   " + test) if problem.is_empty() else ("FAIL %s: %s" % [test, problem]))
		if not problem.is_empty():
			failures += 1
		bridge.stop()
		bridge.free()
	print("%d failed" % failures)
	quit(1 if failures > 0 else 0)


func _start_bridge(port: int = -1) -> void:
	bridge = Bridge.new()
	bridge.host = FakeHost.new()
	bridge.token = "secret"
	bridge.port = port
	bridge.autostart = false
	root.add_child(bridge)
	bridge.start()


## Send `chunks` (written one per frame), return the parsed reply or {"_closed": true}.
func request(chunks: Array, timeout_ms: int = 3000) -> Dictionary:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", bridge.get_port())
	var pending := []
	for chunk: Variant in chunks:
		pending.append(chunk if chunk is PackedByteArray else str(chunk).to_utf8_buffer())
	var offset := 0
	var received := PackedByteArray()
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			# Partial writes, one slice per frame: put_data blocks until everything is sent, and
			# the bridge reading the other end runs on this same thread.
			if not pending.is_empty():
				var data: PackedByteArray = pending[0]
				var wrote: Array = peer.put_partial_data(data.slice(offset, offset + 65536))
				if wrote[0] == OK:
					offset += int(wrote[1])
				if offset >= data.size():
					pending.pop_front()
					offset = 0
			var available := peer.get_available_bytes()
			if available > 0:
				received.append_array(peer.get_data(available)[1])
				if received.find(10) != -1:
					break
		elif status != StreamPeerTCP.STATUS_CONNECTING:
			break
		await process_frame
	peer.disconnect_from_host()
	if received.is_empty():
		return {"_closed": true}
	return JSON.parse_string(received.get_string_from_utf8())


func line(payload: Dictionary) -> String:
	return JSON.stringify(payload) + "\n"


func test_hello_and_invoke():
	var hello := await request([line({"id": 1, "token": "secret", "method": "hello"})])
	if hello.get("commands", []).size() != 1:
		return "hello: %s" % hello
	var out := await request([line({"id": 2, "token": "secret", "method": "invoke", "cmd": "say", "args": ["a", "b"], "stdin": "!"})])
	return "" if out.get("stdout") == "a b!" else "invoke: %s" % out


func test_wrong_token():
	var out := await request([line({"id": 1, "token": "nope", "method": "hello"})])
	return "" if out.get("error") == "Unauthorized" else str(out)


func test_free_port():
	if bridge.get_port() <= 0:
		return "no port chosen"
	var other := Bridge.new()
	other.host = FakeHost.new()
	other.port = -1
	other.autostart = false
	root.add_child(other)
	var err: int = other.start()
	var port: int = other.get_port()
	other.stop()
	other.free()
	if err != OK or port == bridge.get_port():
		return "second bridge: err %d port %d" % [err, port]
	return ""


## A multi-byte character split across two reads must arrive intact.
func test_split_utf8():
	var text := "naïve “quotes” ✓"
	var bytes := line({"id": 1, "token": "secret", "method": "invoke", "cmd": "say", "args": [text]}).to_utf8_buffer()
	var cut := bytes.find("ï".to_utf8_buffer()[0]) + 1 # inside the two-byte ï
	var out := await request([bytes.slice(0, cut), bytes.slice(cut)])
	return "" if out.get("stdout") == text else "got %s" % out


func test_oversized_request():
	bridge.max_request_bytes = 4096
	var big := PackedByteArray()
	big.resize(8192)
	big.fill(65)
	var out := await request([big])
	return "" if out.get("error") == "Request too large" else str(out)


func test_idle_connection():
	bridge.idle_timeout_ms = 200
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", bridge.get_port())
	var start := Time.get_ticks_msec()
	var connected := false
	while Time.get_ticks_msec() - start < 3000:
		peer.poll()
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED and not connected:
			connected = true
			peer.put_data("{\"id\":1".to_utf8_buffer()) # never finishes the line
		elif connected and status != StreamPeerTCP.STATUS_CONNECTED:
			return ""
		# A closed socket can still read as connected until a read sees EOF.
		if connected and peer.get_available_bytes() == 0 and Time.get_ticks_msec() - start > 600:
			var probe: Array = peer.get_partial_data(1)
			if probe[0] != OK:
				return ""
		await process_frame
	return "not closed within 3 s"


func test_connection_flood():
	bridge.max_connections = 4
	var peers := []
	for i in 12:
		var peer := StreamPeerTCP.new()
		peer.connect_to_host("127.0.0.1", bridge.get_port())
		peers.append(peer)
	for i in 10:
		await process_frame
		for peer: StreamPeerTCP in peers:
			peer.poll()
	var held: int = bridge._conns.size()
	for peer: StreamPeerTCP in peers:
		peer.disconnect_from_host()
	for i in 5:
		await process_frame
	if held > 4:
		return "held %d connections" % held
	var out := await request([line({"id": 1, "token": "secret", "method": "hello"})])
	return "" if out.has("commands") else "no service after the flood: %s" % out


func test_config_keys():
	var dir := OS.get_environment("MCP_SH_CONFIG_DIR")
	if dir.is_empty():
		return "MCP_SH_CONFIG_DIR not set by the test driver"
	DirAccess.make_dir_recursive_absolute(dir.path_join("godot"))
	var file := FileAccess.open(dir.path_join("godot/bridge.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"port": -1, "maxRequestBytes": 2048, "maxConnections": 3, "idleTimeoutMs": 500}))
	file.close()
	var cfg = BridgeConfig.load_config()
	var got := [cfg.port, cfg.max_request_bytes, cfg.max_connections, cfg.idle_timeout_ms]
	return "" if got == [-1, 2048, 3, 500] else "config read %s" % str(got)
