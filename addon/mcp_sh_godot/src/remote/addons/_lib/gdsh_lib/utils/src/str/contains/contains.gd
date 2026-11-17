extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/match_base.gd"

const _HELP = \
"Keep inputs that contain a substring; -b only sets the exit code.
Quote a substring that starts with '-'.
Usage: str contains [-b] [-i] <substring> [text]"


static func get_command_name() -> String:
	return "contains"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:1,max:2",
	})


func _matches(text:String, needle:String) -> bool:
	return text.contains(needle)

