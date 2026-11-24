extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/utils/cmd/str/match_base.gd"

const _HELP = \
"Keep inputs that begin with a prefix; -b only sets the exit code.
Quote a prefix that starts with '-'.
Usage: str begins_with [-b] [-i] <prefix> [text]"


static func get_command_name() -> String:
	return "begins_with"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:1,max:2",
	})


func _matches(text:String, needle:String) -> bool:
	return text.begins_with(needle)

