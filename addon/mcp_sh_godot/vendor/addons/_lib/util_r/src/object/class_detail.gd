

const UString = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/util_r/src/string/u_string.gd") #! resolve UtilR.Strings.UString

enum IncludeInheritance{
	NONE,
	SCRIPTS_ONLY,
	ALL,
	
}

enum PreloadSearch{
	PRELOAD,
	INNER_CLASS,
	ALL,
}

const _PROP_USAGE_FLAGS = PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_INTERNAL

const _MEMBER_ARGS = ["signal", "property", "method", "enum", "const"]
const _INVALID_DATA = "__INVALID_DATA__"

static var global_class_registry:Dictionary = {}
static var initialized := false


static func connect_fs_signal():
	if initialized:
		return
	# Populate before any editor check: the registry is needed at runtime too, where there is no
	# EditorInterface and no filesystem_changed signal to ever fill it in.
	_build_global_class_registry()
	if not Engine.is_editor_hint():
		initialized = true
		return
	var editor_interface = Engine.get_singleton("EditorInterface")
	if not is_instance_valid(editor_interface):
		# Not ready yet during editor startup. Leave initialized false so a later lookup retries
		# and still gets the filesystem_changed connection.
		return
	var fs = editor_interface.get_resource_filesystem()
	if not fs.filesystem_changed.is_connected(_build_global_class_registry):
		fs.filesystem_changed.connect(_build_global_class_registry)
	initialized = true

static func _build_global_class_registry():
	global_class_registry = get_all_global_class_paths()


static func class_get_all_members(script:GDScript):
	if script == null:
		printerr("UCLASS DETAIL - NULL SCRIPT PASSED - class_get_all_members")
		return {}
	var members = _recur_get_class_members(script)
	return members

static func class_get_all_signals(script:GDScript):
	if script == null:
		printerr("UCLASS DETAIL - NULL SCRIPT PASSED - class_get_all_signals")
		return {}
	var members = _recur_get_class_members(script, ["signal"])
	return members

static func class_get_all_properties(script:GDScript):
	if script == null:
		printerr("UCLASS DETAIL - NULL SCRIPT PASSED - class_get_all_properties")
		return {}
	var members = _recur_get_class_members(script, ["property"])
	return members

static func class_get_all_methods(script:GDScript):
	if script == null:
		printerr("UCLASS DETAIL - NULL SCRIPT PASSED - class_get_all_methods")
		return {}
	var members = _recur_get_class_members(script, ["method"])
	return members

static func class_get_all_constants(script:GDScript):
	if script == null:
		printerr("UCLASS DETAIL - NULL SCRIPT PASSED - class_get_all_constants")
		return {}
	var members = _recur_get_class_members(script, ["const"])
	return members

static func class_get_all_enums(script:GDScript):
	if script == null:
		printerr("UCLASS DETAIL - NULL SCRIPT PASSED - class_get_all_enums")
		return {}
	var members = _recur_get_class_members(script, ["enum"])
	return members


static func _recur_get_class_members(script:Script, desired_members:=_MEMBER_ARGS, get_class_data:=true):
	var members_dict = {}
	
	if get_class_data:
		var instance_type = script.get_instance_base_type()
		if instance_type == null:
			return {}
		members_dict.merge(get_members_of_base_type(instance_type, desired_members))
		#if "signal" in desired_members:
			#var class_signals = ClassDB.class_get_signal_list(instance_type)
			#for data in class_signals:
				#var name = data.get("name")
				#members_dict[name] = data
		#if "property" in desired_members:
			#var class_properties = ClassDB.class_get_property_list(instance_type)
			#for data in class_properties:
				#var name = data.get("name")
				#var usage = data.get(&"usage")
				#if usage & _PROP_USAGE_FLAGS:
					#continue
				#if name.is_empty():
					#printerr("PROPERTY NM IS BLANK: ", data)
					#continue
				#members_dict[name] = data
		#if "method" in desired_members:
			#var class_methods = ClassDB.class_get_method_list(instance_type)
			#for data in class_methods:
				#var name = data.get("name")
				#members_dict[name] = data
		#if "enum" in desired_members:
			#var class_enums = ClassDB.class_get_enum_list(instance_type)
			#for i in class_enums:
				#members_dict[i] = ClassDB.class_get_enum_constants(instance_type, i)
		#if "const" in desired_members:
			#var const_map = ClassDB.class_get_integer_constant_list(instance_type)
			#for i in const_map:
				#members_dict[i] = ClassDB.class_get_integer_constant(instance_type, i)
	
	var base_script = script.get_base_script()
	if base_script == null:
		#var members_array = members_dict.keys()
		return members_dict
	
	# get script members every script
	var script_members = _get_script_members(base_script, desired_members)
	for i in script_members.keys():
		members_dict[i] = script_members[i]
	
	# get class members only once
	var get_class_members = false
	var recurs_dict = _recur_get_class_members(base_script, desired_members, get_class_members)
	for i in recurs_dict.keys():
		members_dict[i] = recurs_dict[i]
	
	return members_dict

static func get_members_of_base_type(base_type:StringName, desired_members:=_MEMBER_ARGS):
	var members_dict: = {}
	if "signal" in desired_members:
		var class_signals = ClassDB.class_get_signal_list(base_type)
		for data in class_signals:
			var name = data.get("name")
			members_dict[name] = data
	if "property" in desired_members:
		var class_properties = ClassDB.class_get_property_list(base_type)
		for data in class_properties:
			var name = data.get("name")
			var usage = data.get(&"usage")
			if usage & _PROP_USAGE_FLAGS:
				continue
			if name.is_empty():
				printerr("PROPERTY NM IS BLANK: ", data)
				continue
			members_dict[name] = data
	if "method" in desired_members:
		var class_methods = ClassDB.class_get_method_list(base_type)
		for data in class_methods:
			var name = data.get("name")
			members_dict[name] = data
	if "enum" in desired_members:
		var class_enums = ClassDB.class_get_enum_list(base_type)
		for i in class_enums:
			members_dict[i] = ClassDB.class_get_enum_constants(base_type, i)
	if "const" in desired_members:
		var const_map = ClassDB.class_get_integer_constant_list(base_type)
		for i in const_map:
			members_dict[i] = ClassDB.class_get_integer_constant(base_type, i)
	return members_dict

static func script_get_all_members(script:GDScript, include_inheritance:=IncludeInheritance.NONE):
	if script == null:
		printerr("UCLASS DETAIL - NULL SCRIPT PASSED - script_get_all_members")
		return {}
	var members = _get_script_members(script)
	if include_inheritance == IncludeInheritance.ALL:
		members.merge(_recur_get_class_members(script,_MEMBER_ARGS))
	elif include_inheritance == IncludeInheritance.SCRIPTS_ONLY:
		members.merge(_recur_get_class_members(script,_MEMBER_ARGS, false))
	
	return members

static func script_get_all_signals(script:GDScript, include_inheritance:=IncludeInheritance.NONE):
	if script == null:
		printerr("UCLASS DETAIL - NULL SCRIPT PASSED - script_get_all_signals")
		return {}
	var members = _get_script_members(script, ["signal"])
	if include_inheritance == IncludeInheritance.ALL:
		members.merge(_recur_get_class_members(script,["signal"]))
	elif include_inheritance == IncludeInheritance.SCRIPTS_ONLY:
		members.merge(_recur_get_class_members(script,["signal"], false))
	return members

static func script_get_all_properties(script:GDScript, include_inheritance:=IncludeInheritance.NONE):
	if script == null:
		printerr("UCLASS DETAIL - NULL SCRIPT PASSED - script_get_all_properties")
		return {}
	var members = _get_script_members(script, ["property"])
	if include_inheritance == IncludeInheritance.ALL:
		members.merge(_recur_get_class_members(script,["property"]))
	elif include_inheritance == IncludeInheritance.SCRIPTS_ONLY:
		members.merge(_recur_get_class_members(script,["property"], false))
	return members

static func script_get_all_methods(script:GDScript, include_inheritance:=IncludeInheritance.NONE):
	if script == null:
		printerr("UCLASS DETAIL - NULL SCRIPT PASSED - script_get_all_methods")
		return {}
	var members = _get_script_members(script, ["method"])
	if include_inheritance == IncludeInheritance.ALL:
		members.merge(_recur_get_class_members(script,["method"]))
	elif include_inheritance == IncludeInheritance.SCRIPTS_ONLY:
		members.merge(_recur_get_class_members(script,["method"], false))
	return members

static func script_get_all_constants(script:GDScript, include_inheritance:=IncludeInheritance.NONE):
	if script == null:
		printerr("UCLASS DETAIL - NULL SCRIPT PASSED - script_get_all_constants")
		return {}
	var members = _get_script_members(script, ["const"])
	if include_inheritance == IncludeInheritance.ALL:
		members.merge(_recur_get_class_members(script,["const"]))
	elif include_inheritance == IncludeInheritance.SCRIPTS_ONLY:
		members.merge(_recur_get_class_members(script,["const"], false))
	return members

static func script_get_all_enums(script:GDScript, include_inheritance:=IncludeInheritance.NONE):
	if script == null:
		printerr("UCLASS DETAIL - NULL SCRIPT PASSED - script_get_all_enums")
		return {}
	var members = _get_script_members(script, ["enum"])
	if include_inheritance == IncludeInheritance.ALL:
		members.merge(_recur_get_class_members(script,["enum"]))
	elif include_inheritance == IncludeInheritance.SCRIPTS_ONLY:
		members.merge(_recur_get_class_members(script,["enum"], false))
	return members


static func _get_script_members(script:GDScript, desired_members:=_MEMBER_ARGS):
	var members_dict = {}
	if "signal" in desired_members:
		var script_members = script.get_script_signal_list()
		for data in script_members:
			var name = data.get("name")
			members_dict[name] = data
	if "method" in desired_members:
		var script_method_list = script.get_script_method_list()
		for data in script_method_list:
			var name = data.get("name")
			members_dict[name] = data
	if "property" in desired_members:
		var script_property_list = script.get_script_property_list()
		for data in script_property_list:
			var name = data.get("name")
			var usage = data.get(&"usage")
			if usage & _PROP_USAGE_FLAGS:
				continue
			if name.is_empty():
				continue
			members_dict[name] = data
		#var script_other_list = script.get_property_list() # this needs to deal with the fact that it includes inherited
		#for data in script_other_list:
			#var name = data.get("name")
			#var usage = data.get(&"usage")
			#if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				#if name.is_empty():
					#continue
				#members_dict[name] = data
	if "const" in desired_members:
		var const_dict = script.get_script_constant_map()
		for name in const_dict.keys():
			var value = const_dict.get(name)
			members_dict[name] = value
	if "enum" in desired_members:
		var const_dict = script.get_script_constant_map()
		for name in const_dict.keys():
			var value = const_dict.get(name)
			if value is not Dictionary:
				continue
			if _check_dict_is_enum(value):
				members_dict[name] = value
	
	return members_dict

static func check_dict_is_enum(dict:Dictionary) -> bool:
	return _check_dict_is_enum(dict)

static func _check_dict_is_enum(dict:Dictionary) -> bool:
	var count = 0
	for i in dict.values():
		if i is not int:
			return false
		#if i != count: # these can be out of order if defined so
			#return false
		count += 1
	return true

#static func get_member_info_by_path(script, member_name:String, member_hints_array:=_MEMBER_ARGS, 
				#print_err:=false, force_script_conversion:=false, check_class:=true, check_global:=true):
	#if script == null:
		#printerr("UCLASS DETAIL - NULL SCRIPT PASSED")
		#return null
	##var t = ALibRuntime.Utils.UProfile.TimeFunction.new("Expr: " + member_name)
	##var expr_res = get_member_info_by_path_expr(script, member_name)
	##if expr_res != null:
		##print("RESULT ", expr_res)
		##t.stop()
		##return expr_res
	#var t2 = ALibRuntime.Utils.UProfile.TimeFunction.new("Std: " + member_name)
	#var std_res = _get_member_info_by_path(script, member_name, member_hints_array, print_err, force_script_conversion, check_class, check_global)
	#if t2 != null:
		#t2.stop()
	#return std_res

static func get_member_info_by_path_expr(script:GDScript, member_name):
	var _call = member_name

	if member_name.find(".") > -1:
		var first_script_name = UString.get_member_access_front(member_name)
		var first_script_path = get_global_class_path(first_script_name)
		if first_script_path != "":
			script = load(first_script_path)
			_call = UString.trim_member_access_front(member_name)
	
	var ex = Expression.new()
	var err = ex.parse(_call)
	if err == OK:
		var res = ex.execute([], script, false)
		if ex.has_execute_failed():
			return null
		return res
	return null

static func resolve_script_access_path(script:GDScript, member_name:String, 
				print_err:=false, force_script_conversion:=false, check_class:=true, check_global:=true):
	
	if script == null:
		printerr("UCLASS DETAIL - NULL SCRIPT PASSED - resolve_script_access_path")
		return null
	
	var current_script = script as Script
	var parts = [member_name]
	if member_name.find(".") > -1:
		parts = member_name.split(".", false)
	var resolved_path = ""
	var parts_size = parts.size()
	for i in range(parts_size):
		var part = parts[i]
		var member_info = get_member_info(current_script, part, ["const"], check_class)
		#prints(resolved_path, member_info)
		if member_info == null:
			var err = true
			if i == 0 and check_global:
				var global_class_path = get_global_class_path(part)
				if global_class_path != "":
					err = false
					current_script = load(global_class_path)
					resolved_path = current_script.resource_path
			if err:
				if print_err:
					printerr("Member '%s' not found in: %s" % [part, member_name.get_slice(part, 0).trim_suffix(".")])
				return _append_path_tail(resolved_path, i, parts)
		
		elif member_info is GDScript:
			if member_info.resource_path != "":
				current_script = member_info
				resolved_path = current_script.resource_path
				continue
			return _append_path_tail(resolved_path, i, parts)
		else:
			return _append_path_tail(resolved_path, i, parts)
	
	return resolved_path

static func _append_path_tail(current_path:String, start_i:int, parts:PackedStringArray):
	for i in range(start_i, parts.size()):
		var tail_part = parts[i]
		current_path += "." + tail_part
	return current_path.trim_prefix(".").trim_suffix(".")

static func get_member_info_by_path(script:GDScript, member_name:String, member_hints_array:=_MEMBER_ARGS, 
				print_err:=false, force_script_conversion:=false, check_class:=true, check_global:=true):
	
	if script == null:
		printerr("UCLASS DETAIL - NULL SCRIPT PASSED - get_member_info_by_path")
		return null
	
	if not member_hints_array.has("const"): # I think add this so you can search through classes
		member_hints_array.append("const")
	
	var current_script = script as Script
	var final_val
	var parts = [member_name]
	if member_name.find(".") > -1:
		parts = member_name.split(".", false)
	
	var parts_size = parts.size()
	for i in range(parts_size):
		var part = parts[i]
		var static_member = current_script.get(part)
		final_val = static_member
		if static_member is GDScript:
			current_script = static_member
			continue
		
		var member_info = get_member_info(current_script, part, member_hints_array, check_class)
		final_val = member_info
		if member_info == null:
			var err = true
			if i == 0 and check_global:
				var global_class_path = get_global_class_path(part)
				if global_class_path != "":
					current_script = load(global_class_path)
					final_val = current_script # set final val in case only looking up the global, for some reason
					err = false
			
			if err:
				if print_err:
					printerr("Member '%s' not found in: %s" % [part, member_name.get_slice(part, 0).trim_suffix(".")])
				return null
		
		elif member_info is GDScript:
			current_script = member_info
			continue
		elif member_info is Dictionary:
			if not force_script_conversion and i == parts_size -1:
				break
			
			var _class_name = member_info.get("class_name", "")
			if _class_name != "":
				var next_script = get_script_from_property_info(member_info, current_script)
				if next_script == null:
					return null
				current_script = next_script
				final_val = current_script
				continue
		else:
			#printerr("Unhandled class detail - Line 314: ", member_info)
			pass
	
	return final_val


## Load script from property info. Godot built-in returns null. Pass the parent script to parse the source code
## for situations like preload typed vars.
static func get_script_from_property_info(data:Dictionary, parent_script:GDScript=null):
	var _class = data.get("class_name", "")
	if _class != "":
		if _class.begins_with("res://"):
			if _class.find(".gd.") > -1:
				_class = _class.substr(0, _class.find(".gd.") + 3) # + 3 for the extension
			return load(_class)
		else:
			if not ClassDB.class_exists(_class):
				var trimmed = UString.get_member_access_front(_class) # load the global class
				var path = get_global_class_path(trimmed)
				if path != "":
					return load(path)
	
	if parent_script == null:
		return parent_script
	var inherited_scripts = script_get_inherited_scripts(parent_script)
	inherited_scripts.reverse()
	var property_name = data.get("name")
	var target_script = parent_script
	## SEEM THIS IS NOT NEEDED
	#for s in inherited_scripts:
		#print(s.resource_path)
		#var properties = script_get_all_properties(s, IncludeInheritance.NONE)
		#if properties.has(property_name):
			#print("HAS: ", property_name)
			#target_script = s
			#break
	
	#script_get_all_properties(script )
	
	#var script_source = target_script.source_code
	#var var_declaration_idx = script_source.find("var " + property_name)
	#var var_declaration = script_source.substr(var_declaration_idx, script_source.find("\n", var_declaration_idx) - var_declaration_idx)
	#if var_declaration.find(";") > -1:
		#var_declaration = var_declaration.get_slice(";", 0)
	#var var_data = UString.get_var_name_and_type_hint_in_line(var_declaration) # moved to GDScriptParser.MemberParse
	#if var_data != null:
		#var type = var_data[1]
		#print("DOING DEEP SEARCH::", property_name,"::" ,type)
		#var new_member_info = get_member_info_by_path(target_script, type)
		#if new_member_info is GDScript:
			#return new_member_info
	
	return null

static func get_member_info(script, member_name:String, member_hints_array:=_MEMBER_ARGS, check_class:=true):
	return _get_member_info(script, member_name, member_hints_array, check_class)


static func _get_member_info(script:GDScript, member_name:String, member_hints_array:=_MEMBER_ARGS, check_class:=true):
	if script == null:
		printerr("UCLASS DETAIL - NULL SCRIPT PASSED - _get_member_info")
		return null
	
	if check_class:
		var class_check = _get_member_data_class(script, member_name, member_hints_array)
		if class_check is String and class_check != _INVALID_DATA:
			return class_check
		if class_check is not String:
			return class_check
	
	var current_script = script
	while current_script != null:
		var data = _get_member_data_script(current_script, member_name, member_hints_array)
		if data is String and data != _INVALID_DATA:
			return data
		if data is not String:
			return data
		
		current_script = current_script.get_base_script()
	
	return null


static func _get_member_data_script(script:GDScript, member_name:String, member_hints_array:Array):
	if "const" in member_hints_array:
		var const_dict = script.get_script_constant_map()
		if const_dict.has(member_name):
			return const_dict.get(member_name)
	if "property" in member_hints_array:
		var script_property_list = script.get_script_property_list()
		for data in script_property_list:
			var name = data.get("name")
			if name == member_name:
				return data
	if "enum" in member_hints_array:
		var const_dict = script.get_script_constant_map()
		if const_dict.has(member_name):
			var value = const_dict.get(member_name)
			if value is Dictionary:
				if _check_dict_is_enum(value):
					return const_dict.get(member_name)
	if "method" in member_hints_array:
		var script_method_list = script.get_script_method_list()
		for data in script_method_list:
			var name = data.get("name")
			if name == member_name:
				return data
	if "signal" in member_hints_array:
		var script_members = script.get_script_signal_list()
		for data in script_members:
			var name = data.get("name")
			if name == member_name:
				return data
	
	return _INVALID_DATA


static func _get_member_data_class(script:GDScript, member_name:String, member_hints_array:Array):
	var instance_type = script.get_instance_base_type()
	if instance_type == null:
		return _INVALID_DATA
	
	if "const" in member_hints_array:
		if ClassDB.class_has_integer_constant(instance_type, member_name):
			return ClassDB.class_get_integer_constant(instance_type, member_name)
	if "enum" in member_hints_array:
		if ClassDB.class_has_enum(instance_type, member_name):
			return ClassDB.class_get_enum_constants(instance_type, member_name)
	if "method" in member_hints_array:
		if ClassDB.class_has_method(instance_type, member_name):
			var class_methods = ClassDB.class_get_method_list(instance_type)
			for data in class_methods:
				var name = data.get("name")
				if name == member_name:
					return data
	if "property" in member_hints_array:
		var class_properties = ClassDB.class_get_property_list(instance_type)
		for data in class_properties:
			var name = data.get("name")
			if name == member_name:
				return data
	if "signal" in member_hints_array:
		if ClassDB.class_has_signal(instance_type, member_name):
			var class_signals = ClassDB.class_get_signal_list(instance_type)
			for data in class_signals:
				var name = data.get("name")
				if name == member_name:
					return data
	
	return _INVALID_DATA

## Returns dictionary of all classes [name, path]
static func get_all_global_class_paths():
	var class_dict = {}
	var global_class_list = ProjectSettings.get_global_class_list()
	for dict in global_class_list:
		var name = dict.get("class")
		var path = dict.get("path", "")
		class_dict[name] = path
	return class_dict

static func get_global_class_script(class_nm:String):
	var path = get_global_class_path(class_nm)
	if path != "":
		return load(path)

static func get_global_class_path(class_nm:String):
	connect_fs_signal()
	return global_class_registry.get(class_nm, "")

static func get_global_class_name(script_path:String) -> String:
	connect_fs_signal()
	var name:Variant = global_class_registry.find_key(script_path)
	if name != null:
		return name
	return ""

static func _script_get_member_by_value_recur(script:GDScript, value:Variant, deep:=false, member_hints:=_MEMBER_ARGS, checked:={}):
	if checked.has(script):
		return null
	checked[script] = true
	var member = _script_get_member_by_value(script, value, member_hints)
	
	if not deep:
		return member
	if member != null:
		return member
	
	var constants = script_get_all_constants(script, IncludeInheritance.SCRIPTS_ONLY)
	var constants_keys = constants.keys()
	for c in constants_keys:
		var val = constants.get(c)
		if not val is GDScript:
			continue
		
		var next_member = _script_get_member_by_value_recur(val, value, deep, member_hints, checked)
		if next_member != null:
			return c + "." + next_member
	
	return null

## Get access path to a value in the script. Pass value_parent_script to ensure duplicate values from other scripts are not returned.
static func script_get_member_by_value(script:GDScript, value:Variant, deep:=false, member_hints:=_MEMBER_ARGS, breadth_first:=true):
	# For a non-deep search, just check the top-level script
	if not deep:
		return _script_get_member_by_value(script, value, member_hints)
	
	if breadth_first:
		return _script_get_member_by_value_breadth(script, value, member_hints)
	else:
		return _script_get_member_by_value_recur(script, value, deep, member_hints)


static func _script_get_member_by_value_breadth(start_script:GDScript, value: Variant, member_hints:=_MEMBER_ARGS):
	var queue: Array = [{"script": start_script, "path": ""}]
	
	var checked: Dictionary = {start_script: true}
	while not queue.is_empty():
		var current_item = queue.pop_front()
		var current_script = current_item.script
		var current_path = current_item.path as String
		
		var member_name = _script_get_member_by_value(current_script, value, member_hints)
		
		if member_name != null:
			if current_path.is_empty():
				return member_name
			else:
				return current_path + "." + member_name
		
		var constants = script_get_all_constants(current_script, IncludeInheritance.ALL) # TEST, this was set to scripts only, may have some side effects
		for const_name in constants:
			var child_script = constants[const_name]
			if child_script is GDScript and not checked.has(child_script):
				checked[child_script] = true
				
				var next_path = const_name
				if not current_path.is_empty():
					next_path = current_path + "." + const_name
				
				queue.push_back({"script": child_script, "path": next_path})
	
	return null


static func _script_get_member_by_value(script:GDScript, value:Variant, member_hints:=_MEMBER_ARGS):
	var value_type = typeof(value)
	for hint in member_hints:
		var members
		if hint == "const": members = script_get_all_constants(script, IncludeInheritance.ALL)
		elif hint == "enum": members = script_get_all_enums(script, IncludeInheritance.ALL)
		elif hint == "method": members = script_get_all_methods(script, IncludeInheritance.ALL)
		elif hint == "signal": members = script_get_all_signals(script, IncludeInheritance.ALL)
		elif hint == "property": members = script_get_all_properties(script, IncludeInheritance.ALL)
		if not members:
			continue
		var _check = _check_member_value(members, value, value_type)
		if _check != null:
			return _check
	return null

static func _check_member_value(members:Dictionary, value, value_type:int):
	for member in members.keys():
		var member_info = members.get(member)
		if value_type == typeof(member_info):
			#print("IS SAME: ", is_same(member_info, value))
			#print("COMPARE: ", member_info == value)
			if member_info == value:
			#if is_same(member_info, value):
				return member
	return null

## Return an array of paths including the path of script passed.
static func script_get_inherited_script_paths(script:GDScript) -> Array:
	var paths = []
	while script != null:
		paths.append(script.resource_path)
		script = script.get_base_script()
	return paths

static func script_get_inherited_scripts(script:GDScript) -> Array:
	var scripts = []
	while script != null:
		scripts.append(script)
		script = script.get_base_script()
	return scripts

## Returns a Dictionary[name, script] of GDScript constants.
static func script_get_preloads(script:GDScript, deep:=false, include_inner:=false):
	if deep:
		var search := PreloadSearch.PRELOAD 
		if include_inner:
			search = PreloadSearch.ALL
		return _script_get_preloads_bfs(script, search)
	
	var constants = script_get_all_constants(script, IncludeInheritance.SCRIPTS_ONLY)
	var preloads = {}
	for c in constants.keys():
		var val = constants.get(c)
		if not val is GDScript:
			continue
		if val.resource_path != "" or include_inner:
			preloads[c] = val
	
	return preloads

static func _script_get_preloads_bfs(script:GDScript, preload_search:PreloadSearch):
	var preloads = {}
	var queue: Array = [{"script": script, "path": ""}]
	
	var checked = {script: true}
	while not queue.is_empty():
		var current_item = queue.pop_front()
		var current_script = current_item.script
		var current_path = current_item.path as String
		
		var constants = script_get_all_constants(current_script, IncludeInheritance.ALL)
		for const_name in constants:
			var child_script = constants[const_name]
			if child_script is GDScript and not checked.has(child_script):
				checked[child_script] = true
				if preload_search == PreloadSearch.ALL:
					pass
				elif preload_search == PreloadSearch.INNER_CLASS:
					if child_script.resource_path != "":
						continue
				elif preload_search == PreloadSearch.PRELOAD:
					if child_script.resource_path == "":
						continue
				
				var next_path = const_name
				if not current_path.is_empty():
					next_path = current_path + "." + const_name
				preloads[next_path] = child_script
				queue.push_back({"script": child_script, "path": next_path})
	
	
	return preloads

## Return dict [access_path, script]
static func script_get_inner_classes(script:GDScript):
	var classes = _script_get_preloads_bfs(script, PreloadSearch.INNER_CLASS)
	for path in classes.keys():
		var inner_script = classes[path]
		if inner_script.resource_path != "":
			classes.erase(path)
	
	return classes

