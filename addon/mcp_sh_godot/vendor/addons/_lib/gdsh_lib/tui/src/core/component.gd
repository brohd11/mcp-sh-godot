
extends RefCounted
## A stateful BBCode view. Sizes are monospace columns/rows, not pixels.
const TUIMsg = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/tui/tui_msg.gd")
signal redraw_requested

var size:=Vector2i.ZERO
var focused:=false
var hint:String = ""
var _owner:WeakRef
var _finished:=false

func update(_message:TUIMsg) -> bool:
	return false

func view() -> String:
	return ""

func set_size(value:Vector2i) -> void:
	value = value.max(Vector2i.ZERO)
	if size == value: return
	size = value
	request_redraw()

func set_focused(value:bool) -> void:
	if focused == value: return
	focused = value
	request_redraw()

## Optional cleanup hook. Owners call _dispose(), which guarantees one invocation.
func finish() -> void:
	pass

func request_redraw() -> void:
	if not _finished: redraw_requested.emit()

func _dispose() -> void:
	if _finished: return
	_finished = true
	set_focused(false)
	finish()
	_owner = null

static func single_line(text:String) -> String:
	return text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ").replace("\t", " ")

static func escape(text:String) -> String:
	return text.replace("[", "[lb]")

