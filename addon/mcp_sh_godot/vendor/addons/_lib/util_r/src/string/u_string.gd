

const INDENTIFIER_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
const NUMBERS = "0123456789"

const StringMap = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/util_r/src/string/string_map.gd") #! resolve UtilR.Strings.StringMap

static func hash_string(text:String, hash_type:=HashingContext.HASH_SHA256, chars:int=-1):
	var ctx = HashingContext.new()
	ctx.start(hash_type)
	ctx.update(text.to_utf8_buffer())
	var _hash = ctx.finish()
	var hash_encode = _hash.hex_encode()
	if chars > 0:
		hash_encode = hash_encode.substr(0, chars)
	return hash_encode

static func strip_comment(line:String):
	var valid = ""
	var string_char = ""
	for i in range(line.length()):
		var _char = line[i]
		if _char == "'" or _char == '"':
			if string_char != "":
				if _char == string_char:
					string_char = ""
			else:
				string_char = _char
		if _char == "#":
			if string_char == "":
				return valid
		valid += _char
	
	return valid

static func path_joinv(parts:Array):
	var string = ""
	for p in parts:
		string = string.path_join(p)
	return string

static func dot_join(text:String, to_join:String):
	if text == "" or to_join == "":
		return text + to_join
	return text + "." + to_join

static func dot_joinv(string_array:PackedStringArray):
	var text = ""
	for string in string_array:
		text = dot_join(text, string)
	return text


static func rfind_index_safe(text: String, what: String, from: int = -1) -> int:
	var limit = text.length()
	if from > -1:
		limit = from
	
	var max_valid_start = text.length() - what.length()
	if max_valid_start < 0: return -1
	
	var actual_from = min(limit, max_valid_start)
	return text.rfind(what, actual_from)

static func get_member_access_front(text:String, string_map:StringMap=null):
	var dot_idx = text.find(".")
	if dot_idx > -1:
		if text.find("(") > -1:
			if string_map == null:
				string_map = StringMap.create(text)
			var count = 0
			while count < text.length():
				if string_map.bracket_map.has(count):
					var next = string_map.bracket_map[count]
					if next > count:
						count = next
						continue
				var _char = text[count]
				if _char == ".":
					break
				count += 1
			dot_idx = count
		return text.substr(0, dot_idx)
	return text

static func get_member_access_back(text:String, string_map:StringMap=null):
	var dot_idx = text.rfind(".")
	if dot_idx > -1:
		if text.find("(") > -1:
			if string_map == null:
				string_map = StringMap.create(text)
			var count = text.length() -1
			while count >= 0:
				if string_map.bracket_map.has(count):
					var next = string_map.bracket_map[count]
					if next < count:
						count = next
						continue
				var _char = text[count]
				if _char == ".":
					break
				count -= 1
			dot_idx = count
		return text.substr(dot_idx + 1)
	return text

static func trim_member_access_front(text:String, string_map:StringMap=null):
	var dot_idx = text.find(".")
	if dot_idx > -1:
		if text.find("(") > -1:
			if string_map == null:
				string_map = StringMap.create(text)
			var count = 0
			while count < text.length():
				if string_map.bracket_map.has(count):
					var next = string_map.bracket_map[count]
					if next > count:
						count = next
						continue
				var _char = text[count]
				if _char == ".":
					break
				count += 1
			dot_idx = count
		return text.substr(dot_idx + 1)
	return text

static func trim_member_access_back(text:String, string_map:StringMap=null):
	var dot_idx = text.rfind(".")
	if dot_idx > -1:
		if text.find("(") > -1:
			if string_map == null:
				string_map = StringMap.create(text)
			var count = text.length() -1
			while count >= 0:
				if string_map.bracket_map.has(count):
					var next = string_map.bracket_map[count]
					if next < count:
						count = next
						continue
				var _char = text[count]
				if _char == ".":
					break
				count -= 1
			dot_idx = count
		return text.substr(0, dot_idx)
	return text

static func split_member_access(text:String, string_map:StringMap=null):
	if string_map == null:
		string_map = StringMap.create(text)
	var member_parts = []
	var working_member_name = ""
	var count = 0
	while count < text.length():
		if string_map.bracket_map.has(count):
			var next = string_map.bracket_map[count]
			if next > count:
				for i in range(count, next + 1):
					working_member_name += text[i]
				count = next + 1
				continue
		
		var _char = text[count]
		if _char == ".":
			if string_map.string_mask[count] == 0:
				member_parts.append(working_member_name)
				working_member_name = ""
				count += 1
				continue
		working_member_name += _char
		count += 1
	
	if working_member_name != "":
		member_parts.append(working_member_name)
	
	return member_parts


static func string_safe_count(text:String, what:String, from:int=0, to:int=0, string_map:StringMap=null):
	if string_map == null:
		string_map = get_string_map(text)
	var count = 0
	var max_idx = to if to > 0 else text.length()
	var idx = -10
	idx = text.find(what, from)
	while idx != -1 and idx <= max_idx:
		if string_map.string_mask[idx] == 0:
			count += 1
		idx = text.find(what, idx + 1)
	return count

static func string_safe_find(text:String, find:String, start:=0, string_map:StringMap=null):
	if string_map == null:
		string_map = get_string_map(text)
	var idx = -1
	idx = text.find(find, start)
	while idx != -1 and string_map.string_mask[idx] == 1:
		idx = text.find(find, idx + 1)
	return idx

static func string_safe_rfind(text:String, find:String, start:=-1, string_map:StringMap=null):
	if string_map == null:
		string_map = get_string_map(text)
	var idx = -1
	idx = rfind_index_safe(text, find, start)
	while idx != -1 and string_map.string_mask[idx] == 1:
		idx = rfind_index_safe(text, find, idx - 1)
		if idx == 0:
			return -1
	return idx

static func string_safe_split(text:String, delim:String, allow_empty:=false, skip_brackets:=false, string_map:StringMap=null):
	if string_map == null:
		string_map = StringMap.create(text)
	
	var simple_delim = delim.length() == 1
	var delim_check_char = delim[0]
	
	var parts = []
	var working_part_text = ""
	var count = 0
	while count < text.length():
		if skip_brackets and string_map.bracket_map.has(count):
			var next = string_map.bracket_map[count]
			if next > count:
				for i in range(count, next + 1):
					working_part_text += text[i]
				count = next + 1
				continue
		
		var _char = text[count]
		
		if _char == delim_check_char and string_map.string_mask[count] == 0:
			var valid_delim = true
			if not simple_delim:
				for i in range(delim.length()):
					if count + i >= text.length() or text[count + i] != delim[i]:
						valid_delim = false
						break 
			
			if valid_delim:
				parts.append(working_part_text)
				working_part_text = ""
				count += delim.length()
				continue
		
		working_part_text += _char
		count += 1
	
	if working_part_text != "":
		parts.append(working_part_text)
	
	if allow_empty:
		return parts
	var valid_parts = []
	for part in parts:
		if part != "":
			valid_parts.append(part)
	return valid_parts


static func string_safe_split_multi(text:String, delims:Array, allow_empty:=false, skip_brackets:=false, string_map:StringMap=null):
	if string_map == null:
		string_map = StringMap.create(text)
	
	var simple_delim = delims.size() == 1 and delims[0].length() == 1
	var simple_delims = []
	var delim_check_chars = []
	for d in delims:
		var _char = d[0]
		if not _char in delim_check_chars:
			delim_check_chars.append(_char)
		if d.length() == 1:
			simple_delims.append(d)
	
	var parts = []
	var working_part_text = ""
	var count = 0
	while count < text.length():
		if skip_brackets and string_map.bracket_map.has(count):
			var next = string_map.bracket_map[count]
			if next > count:
				for i in range(count, next + 1):
					working_part_text += text[i]
				count = next + 1
				continue
		
		var _char = text[count]
		if string_map.string_mask[count] == 0 and _char in delim_check_chars:
			var valid_delim = true
			if simple_delim or _char in simple_delims:
				pass
			else:
				for delim in delims:
					for i in range(delim.length()):
						if count + i >= text.length() or text[count + i] != delim[i]:
							valid_delim = false
							break 
			
			if valid_delim:
				parts.append(working_part_text)
				working_part_text = ""
				count += 1
				continue
		
		working_part_text += _char
		count += 1
	
	if working_part_text != "":
		parts.append(working_part_text)
	
	if allow_empty:
		return parts
	var valid_parts = []
	for part in parts:
		if part != "":
			valid_parts.append(part)
	return valid_parts


static func remove_comment(text:String, string_safe:=false, string_map:StringMap=null):
	if not string_safe:
		return text.get_slice("#", 0)
	else:
		if string_map == null:
			string_map = get_string_map(text)
		var comment_index = string_safe_find(text, "#", 0, string_map)
		if comment_index > -1:
			text = text.substr(0, comment_index)
	return text


static func get_script_path_and_suffix(script_path:String):
	var array:Array[String] = []
	if not script_path.is_absolute_path():
		return array
	#if not script_path.begins_with("res://"):
		#return []
	var path = script_path
	var suffix = ""
	var gd_idx = script_path.find(".gd.")
	if gd_idx > -1:
		path = script_path.substr(0, gd_idx + 3)
		suffix = script_path.substr(gd_idx + 4)
	array = [path, suffix]
	return array


static func get_paths_in_line(line_text:String):
	var string_map = get_string_map(line_text, StringMap.Mode.STRING)
	var paths = []
	var path_starts = ["res://", "user://", "uid:/"]
	for string:String in string_map.string_map.values():
		for start in path_starts:
			if string.begins_with(start):
				paths.append(string)
				break
	return paths

static func unescape(text: String) -> String:
	var output: PackedStringArray = []
	var _len = text.length()
	var i = 0
	while i < _len:
		var _char = text[i]
		if _char == "\\":
			if i + 1 < _len:
				output.append(text[i + 1])
				i += 2
			else: # Edge case: String ends with a backslash (e.g. "abc\")
				# Just keep it or discard it based on preference. 
				# Usually we keep it if it's not escaping anything.
				output.append(_char)
				i += 1
		else:
			output.append(_char)
			i += 1
	return "".join(output)

static func quote(text:String, string_name:=false):
	var quoted = text
	if not is_string_or_string_name(text):
		quoted = '"' + text + '"'
	if string_name:
		if not quoted.begins_with("&"):
			quoted = "&" + quoted
	return quoted

static func unquote(text:String):
	#return text.trim_prefix('"').trim_prefix("'").trim_suffix('"').trim_suffix("'")
	if text.begins_with("&") and is_string_or_string_name(text):
		text = text.trim_prefix("&")
	
	if text.begins_with("'") and text.ends_with("'"):
		return text.trim_prefix("'").trim_suffix("'")
	elif text.begins_with('"') and text.ends_with('"'):
		return text.trim_prefix('"').trim_suffix('"')
	return text

static func is_string_or_string_name(text:String):
	if text.begins_with("r"):
		text = text.trim_prefix("r")
	elif text.begins_with("&"):
		text = text.trim_prefix("&")
	return (text.begins_with("'") and text.ends_with("'")) or (text.begins_with('"') and text.ends_with('"'))

static func get_string_map(text:String, _mode:StringMap.Mode=StringMap.Mode.FULL, print_err:=false) -> StringMap:
	return StringMap.create(text, _mode, print_err)




static func run_test():
	var code = r'var result = get_tree().get_first_node_in_group("players").call_deferred("set_inventory", {"name": "Potion [Healing]", "effects": ["Regen(5)", 10]}, Callable(self, "_on_set_complete")).get_meta("config_{}".format(["v1", "default"]), "Fallback string with an (unmatched bracket and a fake escape \\")'
	var parse_result = get_string_map(code, StringMap.Mode.FULL)
	print(parse_result.string)
	# Test 1: No errors should be reported.
	# The "unmatched bracket" is inside a string, so it's not a real error.
	assert(not parse_result.has_errors)
	print("Test 1 PASSED: No parsing errors reported.")
	
	# Test 2: Check if the parser correctly ignored brackets inside strings.
	var string_with_brackets_pos = code.find("Potion [Healing]") + 8 # Index of the '['
	assert(parse_result.string_mask[string_with_brackets_pos] == 1) # Must be in a string
	assert(not string_with_brackets_pos in parse_result.bracket_map) # Must NOT be in the bracket map
	print("Test 2 PASSED: Correctly identified brackets in strings as text.")
	
	# Test 3: Check a deeply nested bracket.
	# Let's find the closing ')' of the .format() call.
	var format_close_paren_pos = code.find('default"])') + 9
	var format_open_paren_pos = code.find('(["v1", ')
	assert(parse_result.bracket_map[format_close_paren_pos] == format_open_paren_pos)
	print("Test 3 PASSED: Correctly mapped a deeply nested bracket pair.")

