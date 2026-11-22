extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const TreeUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/tree_util.gd")

const _HELP = \
"Call a method on each stdin node, printing each node's result one per line.
Usage: ... | tree call <method> [args...] [--verbose] [--private] [-- args starting with -]
Arguments convert to the method's parameter types. A void method prints nothing.
Not undoable: the method runs as-is, so prefer 'tree prop' for properties.
--verbose prints 'path = result' instead of the bare result."

var verbose_flag := false
var private_flag := false


static func get_command_name() -> String:
	return "call"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:1",
	})


func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--verbose", {&"short": "v", &"help": "Print 'path = result' instead of the bare result."})
	options.add_option("--private", {&"help": "Allow underscore-prefixed methods."})
	return options.get_options()


func _process_flag(flag:String):
	if flag == "--verbose":
		verbose_flag = true
	elif flag == "--private":
		private_flag = true


func _execute(ctx:Context):
	var method_name:String = positional_args[0]
	if method_name.begins_with("_") and not private_flag:
		ctx.append_error("'%s' is private; pass --private to call it." % method_name)
		return ExitCode.FAIL
	var nodes = TreeUtil.resolve_targets(ctx)
	if nodes.is_empty():
		return ExitCode.FAIL

	var args = positional_args.slice(1) + payload
	var substitute = ctx.host_data.get("substitute_args")
	if substitute is Callable and substitute.is_valid():
		args = substitute.call(args)
	# Errors pass through; per-argument conversion notes would add a line per node.
	var errors_only = _ErrorsOnly.new(ctx)
	var failed := false
	for n in nodes:
		# A checkpoint can yield a frame; skip nodes freed meanwhile.
		if await ctx.checkpoint():
			return ExitCode.CANCELLED
		if not is_instance_valid(n):
			continue
		var outcome = Utils_Method.call_method(errors_only, n, method_name, args)
		if not outcome.ok:
			failed = true
			continue
		if _is_void(n, method_name):
			continue
		var text = str(outcome.result)
		ctx.append_output("%s = %s" % [TreeUtil.path_of(n), text] if verbose_flag else text)
	return ExitCode.FAIL if failed else ExitCode.OK


## Declared void: no return type and not a Variant return.
static func _is_void(n:Node, method_name:String) -> bool:
	var info = Utils_Method.get_method_info(n, method_name)
	var ret:Dictionary = info.get("return", {})
	return ret.get("type", TYPE_NIL) == TYPE_NIL and not (ret.get("usage", 0) & PROPERTY_USAGE_NIL_IS_VARIANT)


class _ErrorsOnly:
	var _ctx
	func _init(ctx) -> void:
		_ctx = ctx
	func append_error(text:String) -> void:
		_ctx.append_error(text)
	func append_output(_text:String) -> void:
		pass



### GDPackage Global Classes
const Utils_Method = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/method_call.gd")

