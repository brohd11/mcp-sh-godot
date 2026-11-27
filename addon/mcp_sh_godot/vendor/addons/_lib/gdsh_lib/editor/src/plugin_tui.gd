extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/tui/src/core/screen_command.gd"
## The interactive list behind `settings plugin`. That command (the backend) owns discovery and
## plugin state and load()s this only for a TUI host, so the CLI bundle never ships the TUI library.
const ListComponent = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/tui/src/components/list.gd")
const _KEYS = "↑↓ Move · PgUp/Dn · Home/End · Enter Toggle · R Refresh · Esc Exit"
var _plugins:Array[Dictionary] = []
var _status_text:String
var _screen:PluginScreen
## The settings plugin command that spawned this.
var backend

class PluginScreen extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/tui/src/core/screen.gd":
	var list = ListComponent.new()
	var _backend:WeakRef
	func _init(command) -> void:
		_backend = weakref(command)
		list.empty_text = "No addon plugin.cfg files found. Press R to refresh."
		add_component(list)
		list.activated.connect(_activate)
		list.selection_changed.connect(_selection_changed)
	func init() -> void:
		_backend.get_ref()._refresh()
	func set_size(value:Vector2i) -> void:
		super(value)
		list.set_size(Vector2i(size.x, maxi(0, size.y - 1)))
	func update(message:TUIMsg) -> bool:
		if message.type == TUIMsg.Type.KEY:
			var key:InputEventKey = message.payload
			if key.pressed and key.keycode == KEY_R:
				if not key.echo: _backend.get_ref()._refresh()
				return true
		return super(message)
	func view() -> String:
		if size.x <= 0 or size.y <= 0: return ""
		var title = "Plugins (%d)" % list.items.size()
		var text = "[color=#9bbfe5]%s[/color]" % title.left(size.x)
		var body = list.view()
		return text + ("\n" + body if not body.is_empty() else "")
	func _activate(_item) -> void:
		var command = _backend.get_ref()
		command._toggle_selected()
		command._update_hint()
	func _selection_changed(_item) -> void:
		_backend.get_ref()._update_hint()


static func get_command_name() -> String:
	return "plugin"


func create_screen() -> Screen:
	_status_text = ""
	_screen = PluginScreen.new(self)
	return _screen


func _refresh() -> void:
	_plugins = backend._list_plugins()
	var host_id = backend._host_plugin_id()
	var items:Array[ListComponent.Item] = []
	for plugin in _plugins:
		plugin.protected = plugin.id == host_id
		plugin.enabled = backend._is_enabled(plugin.id) if plugin.error.is_empty() else false
		var state = "invalid" if not plugin.error.is_empty() else ("enabled " if plugin.enabled else "disabled")
		var label = "%s  %s (%s)%s" % [state, plugin.name, plugin.id, " [host]" if plugin.protected else ""]
		items.append(ListComponent.Item.new(plugin.id, label, plugin))
	_status_text = ""
	_screen.list.set_items(items)
	_update_hint()


func _toggle_selected() -> void:
	var selected = _screen.list.get_selected()
	if selected == null: return
	var id = selected.id
	# Rescan before mutating: the selected addon may have been removed externally.
	_refresh()
	selected = _screen.list.get_selected()
	if selected == null or selected.id != id:
		_status_text = "Plugin disappeared: " + id
		return
	var plugin:Dictionary = selected.payload
	if plugin.protected:
		_status_text = "Editor Console hosts this view and cannot disable itself."
		return
	if not plugin.error.is_empty():
		_status_text = plugin.error
		return
	var target:bool = not backend._is_enabled(id)
	backend._set_enabled(id, target)
	_refresh()
	_status_text = ("Enabled " if target else "Disabled ") + id if backend._is_enabled(id) == target \
			else "Could not change %s; see the editor log." % id


func _update_hint() -> void:
	var selected = _screen.list.get_selected()
	var plugin:Dictionary = selected.payload if selected != null else {}
	if not _status_text.is_empty():
		_screen.hint = _status_text + " · Enter Toggle · R Refresh · Esc Exit"
	elif plugin.get("protected", false):
		_screen.hint = "Editor Console hosts this view (locked) · ↑↓ Move · Esc Exit"
	elif not plugin.get("error", "").is_empty():
		_screen.hint = plugin.error + " · R Refresh · Esc Exit"
	else:
		_screen.hint = _KEYS
	_screen.request_redraw()

