extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"
const Execution = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/execute.gd")

const FUNCTION_KEY = "__function__"
const RETURN_KEY = "__function_return__"

const _HELP = \
"Built in function command. Acts as glue between function and it's contents."

var function_name:String

static func get_command_name():
	return FUNCTION_KEY

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
	})

func _consume_self(ctx:Context) -> ExitCode:
	function_name = _consume_token(ctx)
	return ExitCode.OK

func _get_target_positional_count() -> int:
	return positional_args.size()

func _execute(ctx:Context):
	await Execution._call_function(function_name, ctx, positional_args)
	return ctx.exit_code

