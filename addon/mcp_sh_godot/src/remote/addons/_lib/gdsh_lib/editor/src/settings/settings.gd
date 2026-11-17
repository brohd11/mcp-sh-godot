extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"


const _HELP = \
"Get or set editor/project settings.
Pass-through command — routes to its subcommands."

static func get_command_name():
	return "settings"

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
	})

