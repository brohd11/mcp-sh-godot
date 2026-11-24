
extends RefCounted
## Input and application events delivered to TUICommand.update().

enum Type { INIT, RESIZE, KEY, MOUSE, USER, SIGNAL }
var type:Type
var payload:Variant


func _init(message_type:Type=Type.USER, data:Variant=null) -> void:
	type = message_type
	payload = data

