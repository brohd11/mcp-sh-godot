

var _string:String = ""
var _raw_string:String = ""
var _longest_line:int = -1
var _longest_line_start:int = 0
var _longest_line_end:int = 0

func clear():
	_string = ""
	_raw_string = ""
	return self

func append(text:Variant, color:Color=Color.TRANSPARENT):
	if text is not String:
		text = str(text)
	_raw_string += text
	if color == Color.TRANSPARENT:
		_string += text
		return self
	var color_string = color.to_html()
	_string += "[color=%s]%s[/color]" % [color_string, text]
	return self

func new_line():
	_check_line_length()
	
	_raw_string += "\n"
	_string += "\n"
	return self

func _check_line_length():
	var last_new_line = _raw_string.rfind("\n")
	var line_length = _raw_string.length() - last_new_line
	if line_length > _longest_line:
		_longest_line = line_length
		_longest_line_start = last_new_line + 1
		_longest_line_end = line_length

func get_longest_line():
	_check_line_length()
	if _longest_line <= 0:
		return _raw_string
	return _raw_string.substr(_longest_line_start, _longest_line_end)

func get_raw_string(clear_string:=false):
	if not clear_string:
		return _raw_string
	var tmp = _raw_string
	clear()
	return tmp

func get_string(clear_string:=false):
	if not clear_string:
		return _string
	var tmp = _string
	clear()
	return tmp

func display(clear_string:=true):
	print_rich(_string)
	if clear_string:
		clear()
	return self

