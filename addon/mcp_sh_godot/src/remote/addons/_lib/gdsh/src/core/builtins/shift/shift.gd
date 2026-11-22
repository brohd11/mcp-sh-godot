extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"


const _HELP = \
"Drop the first positional argument of the parent command (gdsh argument shifting)."

static func get_command_name():
	return "shift"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
	})

func _execute(ctx:Context):
	if is_instance_valid(ctx.parent_ctx):
		ctx.parent_ctx.positional_args.pop_front()
	return ExitCode.OK

