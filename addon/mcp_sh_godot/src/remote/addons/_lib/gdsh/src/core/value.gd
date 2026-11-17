extends RefCounted
## String-to-value conversion for command arguments, exposed as GDSh.Utils.Value.
## Useful for typed method arguments or setting a property from console input.

const _TUPLE_SIZES = {
	TYPE_VECTOR2: 2, TYPE_VECTOR2I: 2,
	TYPE_VECTOR3: 3, TYPE_VECTOR3I: 3,
	TYPE_VECTOR4: 4, TYPE_VECTOR4I: 4,
	TYPE_COLOR: 3, TYPE_RECT2: 4, TYPE_RECT2I: 4,
}


## Convert `arg` to `target_type` (a Variant.Type), or return null when it cannot be.
## Strings convert to bools, numbers, StringNames, array literals, tuples ("(1, 2)" or
## "Vector2(1, 2)"), html colors, and other var_to_str forms. For ints, `base_type`
## enables class constants: "SIZE_FILL", "Control.SIZE_FILL", "Control.SizeFlags.SIZE_FILL".
static func convert(arg:Variant, target_type:int, base_type:String="") -> Variant:
	if typeof(arg) == target_type:
		return arg
	if not (arg is String or arg is StringName):
		return null
	var text := str(arg)
	if target_type == TYPE_INT and base_type != "":
		var constant = _class_constant(text, base_type)
		if constant != null:
			return constant
	match target_type:
		TYPE_OBJECT:
			return null
		TYPE_STRING_NAME:
			return StringName(text)
		TYPE_STRING:
			return text
		TYPE_BOOL:
			if text == "true":
				return true
			if text == "false":
				return false
			return null
		TYPE_FLOAT:
			return text.to_float() if text.is_valid_float() else null
		TYPE_INT:
			return text.to_int() if text.is_valid_int() else null
		TYPE_ARRAY:
			if not (text.begins_with("[") and text.ends_with("]")):
				return null
			var array = []
			for part in text.trim_prefix("[").trim_suffix("]").split(",", false):
				var item = part.strip_edges()
				array.append(_unquote(item) if _is_quoted(item) else infer_type(item))
			return array
	if _TUPLE_SIZES.has(target_type):
		if target_type == TYPE_COLOR and text.is_valid_html_color():
			return Color(text)
		var nums := _parse_tuple(text)
		if nums.size() < _TUPLE_SIZES[target_type]:
			return null
		match target_type:
			TYPE_VECTOR2: return Vector2(nums[0], nums[1])
			TYPE_VECTOR2I: return Vector2i(nums[0], nums[1])
			TYPE_VECTOR3: return Vector3(nums[0], nums[1], nums[2])
			TYPE_VECTOR3I: return Vector3i(nums[0], nums[1], nums[2])
			TYPE_VECTOR4: return Vector4(nums[0], nums[1], nums[2], nums[3])
			TYPE_VECTOR4I: return Vector4i(nums[0], nums[1], nums[2], nums[3])
			TYPE_COLOR: return Color(nums[0], nums[1], nums[2], nums[3] if nums.size() > 3 else 1.0)
			TYPE_RECT2: return Rect2(nums[0], nums[1], nums[2], nums[3])
			TYPE_RECT2I: return Rect2i(nums[0], nums[1], nums[2], nums[3])
	# Last resort: Godot's own var_to_str forms, accepted only as the requested type.
	var parsed = str_to_var(text)
	return parsed if typeof(parsed) == target_type else null


## Best-guess value for untyped input: bool, int, float, html color, or the string.
static func infer_type(text:String) -> Variant:
	if text in ["true", "t", "y"]:
		return true
	if text in ["false", "f", "n"]:
		return false
	if text.is_valid_int():
		return text.to_int()
	if text.is_valid_float():
		return text.to_float()
	if text.is_valid_html_color():
		return Color.html(text)
	return text


## Numbers from "(a, b)", "[a, b]", "Type(a, b)" or "a, b"; empty if any part isn't numeric.
static func _parse_tuple(text:String) -> Array:
	text = text.strip_edges()
	var open := text.find("(")
	if open == -1:
		open = text.find("[")
	if open != -1:
		var close := text.rfind(")")
		if close == -1:
			close = text.rfind("]")
		if close > open:
			text = text.substr(open + 1, close - open - 1)
	var out := []
	for part in text.split(",", false):
		var item := part.strip_edges()
		if not item.is_valid_float():
			return []
		out.append(item.to_float())
	return out


## Integer constant named by `text` relative to `base_type`, or null. Dotted names have
## no brackets, so plain splitting is enough.
static func _class_constant(text:String, base_type:String) -> Variant:
	var parts = text.split(".")
	if parts.size() == 1:
		if ClassDB.class_has_integer_constant(base_type, text):
			return ClassDB.class_get_integer_constant(base_type, text)
		return null
	if parts.size() == 3: # Class.Enum.CONSTANT
		return _class_constant(parts[2], parts[0])
	if parts.size() != 2:
		return null
	if ClassDB.class_has_enum(base_type, parts[0]): # Enum.CONSTANT on the base type
		return _class_constant(parts[1], base_type)
	if ClassDB.class_exists(parts[0]): # Class.CONSTANT
		return _class_constant(parts[1], parts[0])
	return null


static func _is_quoted(text:String) -> bool:
	return text.length() >= 2 and text[0] in ["'", '"'] and text[-1] == text[0]


static func _unquote(text:String) -> String:
	return text.substr(1, text.length() - 2)

