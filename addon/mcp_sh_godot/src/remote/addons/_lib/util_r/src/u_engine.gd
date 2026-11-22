

static func get_editor_interface():
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		return Engine.get_singleton(&"EditorInterface")
	return null

