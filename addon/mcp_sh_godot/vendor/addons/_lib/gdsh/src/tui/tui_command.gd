
extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"
## Override update(message) and view(); the base owns execution and the temporary view.
const TUIMsg = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/tui/tui_msg.gd")

signal _completed

var context:Context
## Usable columns and rows at the current font size; excludes the hint footer.
var viewport_size:=Vector2i.ZERO
var hint:String = ""
var _session
var _messages:Array[TUIMsg] = []
var _running:=false
var _initialized:=false
var _status:int = ExitCode.FAIL


func update(_message:TUIMsg) -> void:
	pass


## Return BBCode without changing state. Render only the rows that fit viewport_size.
func view() -> String:
	return ""


## Optional synchronous cleanup, including disconnecting application signal subscriptions.
func finish() -> void:
	pass


## Call on the main thread. Async callbacks can post here; updates never overlap.
func post_message(message:TUIMsg) -> void:
	if not _running or message == null:
		return
	_messages.append(message)
	_session.request_frame()


func quit(exit_code:int=ExitCode.OK) -> void:
	if _running:
		_session.close(exit_code)


func _initialize(ctx:Context):
	super(ctx)
	context = ctx


func _execute(ctx:Context):
	context = ctx
	return await run()


## Enter the interactive mode from _execute(). Returns when the session closes.
## Normal command dispatch supplies context even when _execute() is overridden.
func run() -> int:
	if _running:
		context.append_error("%s: a TUI run is already active" % get_command_name())
		return ExitCode.FAIL
	if context == null:
		return ExitCode.FAIL
	var ctx = context
	var begin = ctx.host_data.get("tui_begin")
	if not (begin is Callable and begin.is_valid()):
		ctx.append_error("%s: an interactive console view is required" % get_command_name())
		return ExitCode.FAIL
	_session = begin.call(ctx)
	if _session == null:
		return ExitCode.FAIL
	_running = true
	_initialized = false
	_status = ExitCode.FAIL
	_messages.clear()
	viewport_size = Vector2i.ZERO
	_session.closed.connect(_on_closed)
	_session.input_event.connect(_on_input)
	_session.frame_requested.connect(_pump)
	_session.request_frame()
	await _completed
	_session = null
	return _status


func _on_input(event:InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_C and event.ctrl_pressed:
		quit(ExitCode.FAIL)
		return
	post_message(TUIMsg.new(TUIMsg.Type.KEY if event is InputEventKey else TUIMsg.Type.MOUSE, event))


func _pump() -> void:
	if not _running:
		return
	# Container layout can settle after acquisition. Never initialize with unknown dimensions.
	if _session.display.size.x <= 0 or _session.size.y <= 0:
		_session.request_frame()
		return
	# The footer can consume all available height. Zero rows is a usable viewport:
	# keep delivering input so the program can still exit or respond to a resize.
	var dimensions:Vector2i = _session.get_viewport_size_in_cells()
	var batch:Array[TUIMsg] = []
	if not _initialized:
		_initialized = true
		viewport_size = dimensions
		batch.append(TUIMsg.new(TUIMsg.Type.INIT))
	elif viewport_size != dimensions:
		viewport_size = dimensions
		batch.append(TUIMsg.new(TUIMsg.Type.RESIZE, dimensions))
	batch.append_array(_messages)
	_messages = [] # Messages posted by update() belong to the next frame.
	for message in batch:
		update(message)
		if not _running:
			return
	var frame = view()
	if not _running:
		return
	if _session.display.text != frame:
		_session.display.text = frame
	_session.display.get_v_scroll_bar().value = 0
	if _session.hint.text != hint:
		_session.hint.text = hint


func _on_closed(value:Variant) -> void:
	if not _running:
		return
	_running = false
	_status = value if value is int else ExitCode.FAIL
	_messages.clear()
	finish()
	_completed.emit()

