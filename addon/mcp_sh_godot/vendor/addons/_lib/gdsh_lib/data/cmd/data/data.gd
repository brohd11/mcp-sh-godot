extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Convert data files between JSON, YAML and Godot binary, and read, write or check ConfigFiles.
Pass-through command — routes to its subcommands."

static func get_command_name():
	return "data"

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
	})

