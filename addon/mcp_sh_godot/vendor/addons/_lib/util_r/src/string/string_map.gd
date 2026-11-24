

const StringMap = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/util_r/src/string/string_map.gd") #! resolve UtilR.Strings.StringMap
const UString = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/util_r/src/string/u_string.gd") #! resolve UtilR.Strings.UString

const BRACKETS = { "(": ")", "[": "]", "{": "}" }
enum Mode {
	FULL,
	STRING,
}

static func create(text:String, _mode:Mode=Mode.FULL, print_err:bool=false) -> StringMap:
	
	if not ClassDB.class_exists("StringMapNative"):
		return new(text, _mode, print_err)
	else:
		# this is on average faster than just gdscript. Occasionally, gd is quicker.
		var smn = ClassDB.class_call_static("StringMapNative", "create", text, _mode, print_err)
		var map:StringMap = new(text, _mode, print_err, false)
		map.string_mask = smn.string_mask
		map.string_map = smn.string_map
		map.quote_map = smn.quote_map
		map.bracket_map = smn.bracket_map
		map.has_errors = smn.has_errors
		map.comment_mask = smn.comment_mask
		
		return map

## Copy of text that was parsed.
var string:String
## A mask where 1 means "inside a string" and 0 means "outside".
var string_mask: PackedByteArray
## A dictionary mapping start index of each string to the strings content, raw: escapes kept as written.
var string_map:Dictionary
## A dictionary mapping a quote's index to its matching partner's index.
var quote_map: Dictionary
## A dictionary mapping each bracket's index to the index of its matching partner.
var bracket_map: Dictionary
## A flag to indicate if any parsing errors (like mismatched brackets) occurred.
var has_errors: bool = false
## Select full scan or only string mask
var mode:Mode
## A mask where 1 is after a comment and before newline
var comment_mask:PackedByteArray


func _init(text:String, _mode:Mode=Mode.FULL, print_err:=false, parse:=true) -> void:
	string = text
	mode = _mode
	if parse:
		_parse(text, print_err)

func _parse(text: String, print_err:=false):
	var text_length = text.length()
	string_mask.resize(text_length)
	comment_mask.resize(text_length)
	
	var bracket_values = BRACKETS.values()
	var bracket_stack = []
	var in_comment = false
	var in_string = false
	var in_triple_quote = false
	var quote_char = ""
	var string_start_index = -1
	
	var i = -1 # for easy indexing
	while i + 1 < text_length:
		i += 1
		var _char = text[i]
		if in_comment:
			if _char == "\n":
				in_comment = false
			else:
				comment_mask[i] = 1
		elif in_string:
			string_mask[i] = 1
			if _char == "\\":
				if i + 1 < text_length:
					string_mask[i + 1] = 1
					i += 1
			elif _char == quote_char and (not in_triple_quote or
					(i + 2 < text_length and text[i + 1] == quote_char and text[i + 2] == quote_char)):
				var delimiter_length = 3 if in_triple_quote else 1
				var content_start = string_start_index + delimiter_length
				string_map[string_start_index] = text.substr(content_start, i - content_start)
				for j in range(1, delimiter_length):
					string_mask[i + j] = 1
				i += delimiter_length - 1
				in_string = false
				in_triple_quote = false
				quote_map[string_start_index] = i
				quote_map[i] = string_start_index
		else: # not in_string
			if _char == '"' or _char == "'":
				in_string = true
				quote_char = _char
				string_start_index = i
				string_mask[i] = 1
				in_triple_quote = i + 2 < text_length and text[i + 1] == _char and text[i + 2] == _char
				if in_triple_quote:
					string_mask[i + 1] = 1
					string_mask[i + 2] = 1
					i += 2
			elif _char == "#":
				in_comment = true
				comment_mask[i] = 1
			elif mode == Mode.FULL:
				if _char in BRACKETS:
					bracket_stack.push_back(i)
				elif _char in bracket_values:# bracket closing
					if bracket_stack.is_empty():
						has_errors = true
						break
					var open_idx = bracket_stack.pop_back()
					if BRACKETS[text[open_idx]] == _char:
						bracket_map[open_idx] = i
						bracket_map[i] = open_idx
					else:
						has_errors = true
						break
	
	# after loop
	if in_string:
		if print_err:
			printerr("Unterminated string starting at index ", string_start_index)
		has_errors = true
	if not bracket_stack.is_empty():
		if print_err:
			printerr("Unclosed opening bracket at index ", bracket_stack.front())
		has_errors = true

func index_in_string_or_comment(index:int):
	if comment_mask[index] == 1:
		return true
	if string_mask[index] == 1:
		return true
	return false

func get_comment_index(from:int=0):
	return comment_mask.find(1, from)

func get_line_at_index(index:int):
	var beginning_new_line_i = UString.rfind_index_safe(string, "\n", index)
	if beginning_new_line_i == -1:
		beginning_new_line_i = 0
	var end_new_line_i = string.find("\n", index)
	if end_new_line_i == -1:
		end_new_line_i = string.length() - 1
	return string.substr(beginning_new_line_i, end_new_line_i - beginning_new_line_i)

func get_strings():
	return string_map.values()

func get_tightest_bracket_set(idx:int, bracket_type:=""):
	var all_brackets = bracket_type == ""
	var open_bracket_index = -1
	var closed_bracket_index = string.length()
	var bracket_map_keys = bracket_map.keys()
	bracket_map_keys.sort()
	
	for open in bracket_map_keys:
		if open > idx:
			break
		var _char = string[open]
		if not all_brackets and _char != bracket_type:
			continue
		var close = bracket_map.get(open)
		if not (open <= idx and close >= idx):
			continue
		
		if close - open < closed_bracket_index - open_bracket_index:
			open_bracket_index = open
			closed_bracket_index = close
	
	return open_bracket_index
	
	

