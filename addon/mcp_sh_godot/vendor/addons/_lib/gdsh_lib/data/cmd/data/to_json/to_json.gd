extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/data/src/convert_command.gd"

const _HELP = \
"Convert a YAML, JSON or binary file to JSON (written as .json unless a write path is given).
Usage: data to_json [--overwrite] [--no-scan] [--from-bin] " + USAGE_TAIL

static func get_command_name():
	return "to_json"

static func get_self_command_data():
	return _convert_command_data(_HELP)

func _init() -> void:
	format = "json"

