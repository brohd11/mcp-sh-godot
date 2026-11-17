extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const StrUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/str_util.gd")

const _HELP = \
"Character count of each input (String.length). For whole-stdin counts use 'count'.
Usage: str length [text]"


static func get_command_name() -> String:
	return "length"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:0,max:1",
	})


func _execute(ctx:Context):
	return StrUtil.map_lines(ctx, StrUtil.inputs(ctx, positional_args, 0), func(s:String): return s.length())

