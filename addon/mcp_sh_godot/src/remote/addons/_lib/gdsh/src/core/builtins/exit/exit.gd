extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"


const _HELP = \
"Exit process, propogation stops at current 'sub shell'."

static func get_command_name():
	return "exit"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": 1
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
			ctx.append_error("Invalid exit code: " + arg)


	ctx.exit_requested = true
	ctx.exit_code = code

	var inherited = ctx.get_inherited_ctxs()
	for inh in inherited:
		inh.exit_requested = true
		inh.exit_code = code


