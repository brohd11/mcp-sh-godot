
extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/tui/src/core/component.gd"
## A single-row-per-item list. Labels are plain text; selection and scrolling are separate.
class Item extends RefCounted:
	var id:String
	var label:String
	var payload:Variant
	func _init(key:String="", text:String="", data:Variant=null) -> void:
		id = key
		label = text
		payload = data

signal selection_changed(item:Item)
signal activated(item:Item)
var items:Array[Item] = []
var selected_index:int = -1
var first_visible:int = 0
var empty_text:String = "No items."
var _scroll_remainder:=0.0

func _init() -> void:
	hint = "↑↓ Move · PgUp/Dn · Home/End · Enter Select"

func get_selected() -> Item:
	return items[selected_index] if selected_index >= 0 and selected_index < items.size() else null

func set_items(value:Array[Item]) -> void:
	var previous = get_selected()
	var id = previous.id if previous != null else ""
	items = value.duplicate()
	var index = maxi(0, selected_index)
	if previous != null:
		for candidate in items.size():
			if items[candidate].id == id:
				index = candidate
				break
	selected_index = clampi(index, 0, items.size() - 1) if not items.is_empty() else -1
	_reveal_selected()
	selection_changed.emit(get_selected())
	request_redraw()

func select(index:int) -> void:
	var next = clampi(index, 0, items.size() - 1) if not items.is_empty() else -1
	var changed = selected_index != next
	selected_index = next
	_reveal_selected()
	if changed: selection_changed.emit(get_selected())
	request_redraw()

func set_size(value:Vector2i) -> void:
	if size == value.max(Vector2i.ZERO): return
	super(value)
	_reveal_selected()

func _reveal_selected() -> void:
	if selected_index < 0:
		first_visible = 0
		return
	first_visible = clampi(first_visible, maxi(0, selected_index - maxi(1, size.y) + 1), selected_index)
	first_visible = mini(first_visible, maxi(0, items.size() - maxi(1, size.y)))

func update(message:TUIMsg) -> bool:
	if not focused or _finished: return false
	if message.type == TUIMsg.Type.MOUSE:
		var event = message.payload
		var delta:=0.0
		if event is InputEventPanGesture:
			delta = event.delta.y * 3
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: delta = event.factor * 3
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP: delta = -event.factor * 3
			else: return false
		else: return false
		_scroll_remainder += delta
		var steps = int(_scroll_remainder)
		_scroll_remainder -= steps
		first_visible = clampi(first_visible + steps, 0, maxi(0, items.size() - maxi(1, size.y)))
		request_redraw()
		return true
	if message.type != TUIMsg.Type.KEY: return false
	var key:InputEventKey = message.payload
	if not key.pressed: return false
	match key.keycode:
		KEY_UP: select(selected_index - 1)
		KEY_DOWN: select(selected_index + 1)
		KEY_PAGEUP: select(selected_index - maxi(1, size.y))
		KEY_PAGEDOWN: select(selected_index + maxi(1, size.y))
		KEY_HOME: select(0)
		KEY_END: select(items.size() - 1)
		KEY_ENTER, KEY_KP_ENTER:
			if not key.echo and get_selected() != null: activated.emit(get_selected())
		_: return false
	return true

func view() -> String:
	if size.x <= 0 or size.y <= 0: return ""
	if items.is_empty(): return escape(single_line(empty_text).left(size.x))
	var lines:PackedStringArray = []
	for index in range(first_visible, mini(items.size(), first_visible + size.y)):
		var prefix = "> " if index == selected_index else "  "
		var label = escape((prefix + single_line(items[index].label)).left(size.x))
		if index == selected_index and focused:
			label = "[bgcolor=#38577a][color=#ffffff]%s[/color][/bgcolor]" % label
		lines.append(label)
	return "\n".join(lines)

