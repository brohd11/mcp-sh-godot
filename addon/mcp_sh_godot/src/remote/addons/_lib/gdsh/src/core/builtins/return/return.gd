extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"


const _HELP = \
"Return value code for function."

static func get_command_name():
	return "return"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
	})

func _get_target_positional_count() -> int:
	return min(1, positional_args.size())

func _execute(ctx:Context):
	var code = 0
	if positional_args.size() == 1:
		var arg = positional_args[0]
		if arg.is_valid_int():
			code = int(arg)
		else:
			code = ExitCode.ERR
			ctx.append_error("Invalid return code: " + arg)

	ctx.last_status = code
	ctx.exit_code = code
	for inh in ctx.get_inherited_ctxs():
		if inh.data.has("__function__"):
			inh.data["__function_return__"] = code
			inh.last_status = code
			return

	ctx.append_error("Attempted return while not in function.")
	ctx.exit_code = ExitCode.ERR

