extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"


const _HELP = \
"Editor control commands (play, open, scan, …).
Pass-through command — routes to its subcommands."

static func get_command_name():
	return "editor"

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
	})


func _resolve_subcommand(token:String, commands:Dictionary):
	var exact = super._resolve_subcommand(token, commands)
	if exact != null:
		return exact
	return commands.get("script") if token.begins_with("script.") else null

