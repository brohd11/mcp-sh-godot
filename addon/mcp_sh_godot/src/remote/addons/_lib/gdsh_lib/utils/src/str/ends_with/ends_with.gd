extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/match_base.gd"

const _HELP = \
"Keep inputs that end with a suffix; -b only sets the exit code.
Quote a suffix that starts with '-'.
Usage: str ends_with [-b] [-i] <suffix> [text]"


static func get_command_name() -> String:
	return "ends_with"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:1,max:2",
	})


func _matches(text:String, needle:String) -> bool:
	return text.ends_with(needle)

