
extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/tui/src/core/component.gd"
## Owns components and keyboard focus. Subclasses explicitly size and compose views.
const Component = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/tui/src/core/component.gd")
signal navigation_requested(operation:StringName, value:Variant)
var components:Array[Component] = []
var _focus_index:int = -1

func init() -> void:
	pass

func suspend() -> void:
	pass

func resume(_result:Variant) -> void:
	pass

func add_component(component:Component) -> void:
	if _finished or component == null or component == self or component._finished: return
	if component._owner != null and component._owner.get_ref() != null: return
	component._owner = weakref(self)
	components.append(component)
	component.redraw_requested.connect(request_redraw)
	if _focus_index < 0: _focus_index = 0
	_sync_focus()
	request_redraw()

## Removed components are finished and cannot be reused. Covered screens retain theirs.
func remove_component(component:Component) -> void:
	var index = components.find(component)
	if index < 0: return
	components.remove_at(index)
	component.redraw_requested.disconnect(request_redraw)
	component._dispose()
	if index < _focus_index: _focus_index -= 1
	_focus_index = mini(_focus_index, components.size() - 1)
	_sync_focus()
	request_redraw()

func focus_component(component:Component) -> void:
	var index = components.find(component)
	if index < 0: return
	_focus_index = index
	_sync_focus()
	request_redraw()

func get_focused_component() -> Component:
	return components[_focus_index] if _focus_index >= 0 else null

func set_focused(value:bool) -> void:
	super(value)
	_sync_focus()

func _sync_focus() -> void:
	for index in components.size():
		components[index].set_focused(focused and index == _focus_index)

func get_hint() -> String:
	var component = get_focused_component()
	return hint if not hint.is_empty() or component == null else component.hint

func update(message:TUIMsg) -> bool:
	if _finished: return false
	if message.type == TUIMsg.Type.KEY:
		var key:InputEventKey = message.payload
		if key.pressed and key.keycode in [KEY_TAB, KEY_BACKTAB]:
			if not components.is_empty() and not key.echo:
				var backwards = key.shift_pressed or key.keycode == KEY_BACKTAB
				_focus_index = posmod(_focus_index + (-1 if backwards else 1), components.size())
				_sync_focus()
				request_redraw()
			return true
	var component = get_focused_component()
	if component != null and component.update(message): return true
	if message.type == TUIMsg.Type.KEY:
		var key:InputEventKey = message.payload
		if key.pressed and key.keycode == KEY_ESCAPE:
			if not key.echo: pop()
			return true
	return false

func push(screen:Component) -> void:
	if not _finished: navigation_requested.emit(&"push", screen)

func pop(result:Variant=null) -> void:
	if not _finished: navigation_requested.emit(&"pop", result)

func replace(screen:Component) -> void:
	if not _finished: navigation_requested.emit(&"replace", screen)

func _dispose() -> void:
	if _finished: return
	# Disconnect before finishing children: their cleanup cannot schedule new frames.
	for component in components:
		component.redraw_requested.disconnect(request_redraw)
		component._dispose()
	components.clear()
	_focus_index = -1
	super()

