extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"


const _HELP = \
"Returns ExitCode.OK"

static func get_command_name():
	return "true"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
	})

func _execute(ctx:Context):
	return ExitCode.OK

