extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

static func get_command_name() -> String:
	return "pwn"

static func get_self_command_data() -> Dictionary:
	return _command_data({&"discoverable": false, &"help": "Print the current working node path.\nUsage: pwn"})

func _execute(ctx:Context):
	ctx.append_output(ctx.cwn)
	return ExitCode.OK

