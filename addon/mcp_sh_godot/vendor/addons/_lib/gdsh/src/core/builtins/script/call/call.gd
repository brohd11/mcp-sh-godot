extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const TargetUtil = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/target_util.gd")

const _RESULTS_TO_SKIP = ["GDScriptFunctionState"]

var show_private:=false
var inherited:=false
var engine:=false
var create_default:= false

static func get_command_name() -> String:
	return "call"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": TargetUtil.get_usage_string(
			"Call a static script method or a method on a live node",
			"call <options> <method> -- <...args>"
		),
		&"positional_count": 1,
	})

func _get_flags():
	var options = Options.new()
	options.add_option("--private", {
		&"help": "Include private (underscore-prefixed) methods."
	})
	options.add_option("--default", {
		&"help": "Create default value arguments when calling the method."
	})
	options.add_option("--inherited", {&"help": "Complete methods from base scripts (an exact name runs without it)."})
	options.add_option("--engine", {&"help": "Complete base script and engine methods (an exact name runs without it)."})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--private":
		show_private = true
	elif flag == "--inherited":
		inherited = true
	elif flag == "--engine":
		engine = true
	elif flag == "--default":
		create_default = true

func _get_completions(ctx:Completion):
	if ctx.in_arguments():
		var dict = {}
		Options.add_show_variables_to_dict(dict)
		return dict
	if not _positional_arg_index_valid():
		return {}
	if not is_instance_valid(TargetUtil.get_target(ctx.context)):
		return {}

	var flags = get_flags(true)
	var methods = TargetUtil.get_methods_from_ctx(ctx.context, show_private, true, inherited, engine)
	if not ctx.context.unconsumed_tokens.is_empty():
		var current_name = ctx.context.unconsumed_tokens.pop_front()
		if current_name in methods:
			return {}
	for m in methods.keys():
		var meta = methods[m].get_or_add(Options.Keys.METADATA, {})
		if meta.get(Options.Keys.ARG_COUNT, 0) != 0:
			meta[Options.Keys.ADD_ARGS] = true
	methods.merge(flags)
	return methods

func _execute(ctx:Context):
	var method_name = positional_args[0]
	var script = TargetUtil.get_target(ctx)
	if not is_instance_valid(script):
		ctx.append_error(TargetUtil.target_error(ctx))
		return ExitCode.FAIL

	var methods = TargetUtil.get_methods_from_ctx(ctx, show_private, true, inherited, engine)
	# The selectors narrow completion; a typed name is already a deliberate choice. Private stays gated.
	if not method_name in methods:
		methods = TargetUtil.get_methods_from_ctx(ctx, show_private, true, true, true)
	if not method_name in methods:
		ctx.append_error("Unrecognized method: " + method_name)
		return ExitCode.FAIL
	return call_method(ctx, script, method_name)

func call_method(ctx:Context, script, method_name:String):
	# Host hooks, both optional: argument substitution (console $VARs) and a stand-in object for
	# Object parameters when --default fills them in.
	var args = payload.duplicate()
	var substitute = ctx.host_data.get("substitute_args")
	if substitute is Callable and substitute.is_valid():
		args = substitute.call(args)
	var object_default = ctx.host_data.get("object_default")
	if not (object_default is Callable and object_default.is_valid()):
		object_default = Callable()

	# Checks, conversion and declared defaults are GDSh's; the Callable round-trip the editor
	# used to do was pure ceremony, since call_method takes the object and method directly.
	var outcome = Utils_Method.call_method(ctx, script, method_name, args, create_default, object_default)
	if not outcome.ok:
		return ExitCode.FAIL
	var result = outcome.result
	if result != null and not (result is Object and result.get_class() in _RESULTS_TO_SKIP):
		ctx.append_output("GDScript Method Call:")
		ctx.append_output(str(result))
	return ExitCode.OK



### GDPackage Global Classes
const Utils_Method = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/method_call.gd")

