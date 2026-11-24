extends RefCounted
## Call a method on a target object with argument checks and conversion, exposed as
## GDSh.Utils.Method. The target decides what is callable: a Script allows its static
## methods, and any other object (an instance, a node from the tree) allows its own.

const Value = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/value.gd")


## Method info (as from get_method_list) for `method` callable on `target`, or {}.
static func get_method_info(target:Object, method:String) -> Dictionary:
	if not is_instance_valid(target):
		return {}
	if target is Script:
		var info = _script_method(target, method)
		return info if info.get("flags", 0) & METHOD_FLAG_STATIC else {}
	var script = target.get_script()
	if script != null:
		var declared = _script_method(script, method)
		if not declared.is_empty():
			return declared
	var found = {}
	for info in target.get_method_list():
		if info.name == method:
			found = info
	return found


## Call `method` on `target` with `args`, converting mismatched argument types.
## Missing trailing arguments use declared defaults. With `create_default_args`, other
## missing arguments are created: `object_default.call(class_name)` for object parameters
## when valid, otherwise the type's zero value. Errors and conversion notes go to `ctx`.
## Returns {"ok": bool, "result": Variant}; the result is not printed.
static func call_method(ctx, target:Object, method:String, args:Array,
		create_default_args:=false, object_default:=Callable()) -> Dictionary:
	var failed = {"ok": false, "result": null}
	if not is_instance_valid(target):
		_error(ctx, "Cannot call '%s': no target object" % method)
		return failed
	var info = get_method_info(target, method)
	if info.is_empty():
		if target is Script and not _script_method(target, method).is_empty():
			_error(ctx, "'%s' is an instance method; call it on an instance" % method)
		else:
			_error(ctx, "Method '%s' not found on %s" % [method, target])
		return failed

	args = args.duplicate()
	var params:Array = info.get("args", [])
	var defaults:Array = info.get("default_args", [])
	var required = params.size() - defaults.size()
	var vararg = info.get("flags", 0) & METHOD_FLAG_VARARG
	if (args.size() < required and not create_default_args) or (not vararg and args.size() > params.size()):
		_error(ctx, "Arg count mismatch: %s - expected %s, got %s" % [method, params.size(), args.size()])
		return failed

	var valid = true
	for i in range(mini(args.size(), params.size())):
		var param:Dictionary = params[i]
		var type:int = param.get("type", TYPE_NIL)
		if type == TYPE_NIL or typeof(args[i]) == type:
			continue
		var passed = args[i]
		# Enum parameters report their class ("Control.SizeFlags"), which scopes constant names.
		var base_type = str(param.get("class_name", "")).get_slice(".", 0)
		var converted = null if type == TYPE_OBJECT else Value.convert(passed, type, base_type)
		if converted == null:
			_error(ctx, "Arg '%s' type mismatch: %s passed, should be %s" % [param.get("name"), type_string(typeof(passed)), type_string(type)])
			valid = false
			continue
		args[i] = converted
		_note(ctx, "Arg '%s' conversion: %s %s -> %s %s" % [param.get("name"), type_string(typeof(passed)), passed, type_string(type), converted])
	if not valid:
		_error(ctx, "Invalid arguments")
		return failed

	for i in range(args.size(), params.size()):
		var param:Dictionary = params[i]
		if i >= required:
			args.append(defaults[i - required])
		elif param.get("type", TYPE_NIL) == TYPE_OBJECT:
			args.append(object_default.call(str(param.get("class_name", ""))) if object_default.is_valid() else null)
		else:
			args.append(type_convert(null, param.get("type", TYPE_NIL)))
	# A GDScript resource only exposes its own static methods through Callable. Resolve
	# the declaration for inherited static calls, while instance calls keep the live target.
	if target is Script:
		while not target.has_method(method):
			target = target.get_base_script()
	return {"ok": true, "result": Callable(target, method).callv(args)}


static func _script_method(script:Script, method:String) -> Dictionary:
	for info in script.get_script_method_list():
		if info.name == method:
			return info
	return {}


static func _error(ctx, text:String) -> void:
	if ctx != null:
		ctx.append_error(text)
	else:
		push_error("GDSh.Utils.Method: " + text)


static func _note(ctx, text:String) -> void:
	if ctx != null:
		ctx.append_output(text)

