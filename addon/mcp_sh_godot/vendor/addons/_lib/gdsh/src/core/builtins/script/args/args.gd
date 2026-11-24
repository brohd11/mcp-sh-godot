extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const TargetUtil = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/target_util.gd")

const PrintRich = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/util_r/src/string/print_rich.gd")

const _TYPE_COLOR = Color("4d819a")
const _UNTYPED_COLOR = Color("cc000c")

var show_private:=false
var inherited:=false
var engine:=false


static func get_command_name() -> String:
	return "args"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": TargetUtil.get_usage_string(
			"List the arguments of a method on the target script or node",
			"args <options> <method_name>"
		),
		&"positional_count": 1,
	})


func _get_flags():
	var options = Options.new()
	options.add_option("--private", {
		&"help": "Include private (underscore-prefixed) methods."
	})
	options.add_option("--inherited", {&"help": "Include methods from base scripts."})
	options.add_option("--engine", {&"help": "Include base scripts and engine methods."})
	return options.get_options()


func _process_flag(flag:String):
	if flag == "--private":
		show_private = true
	elif flag == "--inherited":
		inherited = true
	elif flag == "--engine":
		engine = true


func _get_completions(ctx:Completion):
	if not is_instance_valid(TargetUtil.get_target(ctx.context)):
		return {}
	var flags = get_flags(true)
	var methods = TargetUtil.get_methods_from_ctx(ctx.context, show_private, false, inherited, engine)
	if not ctx.context.unconsumed_tokens.is_empty():
		var current_name = ctx.context.unconsumed_tokens.pop_front()
		if current_name in methods:
			return {}
	methods.merge(flags)
	return methods


func _execute(ctx:Context):
	var method_name = positional_args[0]
	var script = TargetUtil.get_target(ctx)
	if not is_instance_valid(script):
		ctx.append_error(TargetUtil.target_error(ctx))
		return ExitCode.FAIL
	var methods = TargetUtil.get_methods_from_ctx(ctx, show_private, false, inherited, engine)
	if not method_name in methods:
		ctx.append_error("Unrecognized method: " + method_name)
		return ExitCode.FAIL
	return list_args(TargetUtil.get_method_info(script, method_name, inherited, engine), ctx)


static func list_args(property_info:Dictionary, ctx:Context):
	var args_array = property_info.get("args", [])
	var vararg = property_info.get("flags", 0) & METHOD_FLAG_VARARG
	if args_array.is_empty() and not vararg:
		ctx.append_output("No args to list.")
		return ExitCode.OK

	var pr = PrintRich.new()
	for dict in args_array:
		var arg_name = dict.get("name")
		var type = type_string(dict.get("type"))
		var color = _UNTYPED_COLOR if type == "Nil" else _TYPE_COLOR
		pr.append(arg_name + ":").append(type, color).append("  ")

	if vararg:
		pr.append("...args", _UNTYPED_COLOR)
	ctx.append_output(pr.get_string())
	return ExitCode.OK

