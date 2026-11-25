extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Read, write and check Godot ConfigFiles (.cfg, project.godot, export_presets.cfg ...).
Pass-through command — routes to its subcommands."

static func get_command_name():
	return "config_file"

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
	})

