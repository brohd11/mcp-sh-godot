extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"
## Discover and route to the bundled commands, independently of root overrides.

const _HELP = "Built-in commands, also accessible directly by name."


static func get_command_name() -> String:
	return "builtins"


static func get_self_command_data() -> Dictionary:
	return _command_data({&"help": _HELP})


func _get_commands() -> Dictionary:
	var commands = _get_commands_in_dir()
	for name in commands.keys():
		if str(name).begins_with("__"):
			commands.erase(name)
	return commands


func _execute(ctx:Context):
	ctx.append_output(get_help_string(true))
	return ExitCode.OK

