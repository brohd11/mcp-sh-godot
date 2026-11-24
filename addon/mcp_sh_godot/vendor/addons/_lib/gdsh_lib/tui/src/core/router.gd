
extends RefCounted
## Navigation is committed after update; only the current screen can request it.
const Screen = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/tui/src/core/screen.gd")
const TUIMsg = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/tui/tui_msg.gd")
signal redraw_requested
signal completed(result:Variant)
var size:=Vector2i.ZERO
var _stack:Array[Screen] = []
var _pending:Array = []
var _navigation:Dictionary = {}
var _dispatching:=false
var _closed:=false

func top() -> Screen:
	return _stack.back() if not _stack.is_empty() else null

func push(screen:Screen) -> void:
	_enqueue(&"push", screen, weakref(top()) if top() != null else null)

func pop(result:Variant=null) -> void:
	if top() != null: _enqueue(&"pop", result, weakref(top()))

func replace(screen:Screen) -> void:
	_enqueue(&"replace", screen, weakref(top()) if top() != null else null)

func set_size(value:Vector2i) -> void:
	size = value.max(Vector2i.ZERO)
	if top() != null:
		var was_dispatching = _dispatching
		_dispatching = true
		top().set_size(size)
		_dispatching = was_dispatching
		if not _dispatching: _drain()

func update(message:TUIMsg) -> void:
	if _closed or top() == null: return
	_dispatching = true
	top().update(message)
	_dispatching = false
	_drain()

func view() -> String:
	return top().view() if top() != null else ""

func get_hint() -> String:
	return top().get_hint() if top() != null else ""

func _enqueue(operation:StringName, value:Variant, source:WeakRef) -> void:
	if _closed: return
	_pending.append([operation, value, source])
	if not _dispatching: _drain()

func _drain() -> void:
	_dispatching = true
	while not _pending.is_empty() and not _closed:
		var entry = _pending.pop_front()
		var source = entry[2].get_ref() if entry[2] != null else null
		# A covered/removed screen cannot navigate the new top, even within one batch.
		if source != top(): continue
		var operation:StringName = entry[0]
		if operation in [&"push", &"replace"]:
			var screen = entry[1] as Screen
			if screen == null or screen._finished or (screen._owner != null and screen._owner.get_ref() != null):
				continue
			if operation == &"replace" and top() != null:
				_remove_top()
			elif top() != null:
				top().set_focused(false)
				top().suspend()
			_mount(screen)
		elif operation == &"pop" and top() != null:
			_remove_top()
			if top() == null:
				_closed = true
				_pending.clear()
				completed.emit(entry[1])
			else:
				top().set_size(size)
				top().set_focused(true)
				top().resume(entry[1])
	_dispatching = false
	_invalidate()

func _mount(screen:Screen) -> void:
	_stack.append(screen)
	screen._owner = weakref(self)
	var handler = _enqueue.bind(weakref(screen))
	_navigation[screen.get_instance_id()] = handler
	screen.navigation_requested.connect(handler)
	screen.redraw_requested.connect(_invalidate)
	screen.set_size(size)
	screen.set_focused(true)
	screen.init()

func _remove_top() -> void:
	var screen = _stack.pop_back()
	screen.navigation_requested.disconnect(_navigation[screen.get_instance_id()])
	_navigation.erase(screen.get_instance_id())
	screen.redraw_requested.disconnect(_invalidate)
	screen._dispose()

func _invalidate() -> void:
	if not _closed: redraw_requested.emit()

func finish() -> void:
	if _closed and _stack.is_empty(): return
	_closed = true
	_pending.clear()
	while not _stack.is_empty(): _remove_top()

