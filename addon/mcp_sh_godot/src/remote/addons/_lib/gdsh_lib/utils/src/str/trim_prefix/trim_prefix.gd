extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const StrUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/str_util.gd")

const _HELP = \
"Remove a prefix if present (String.trim_prefix).
Usage: str trim_prefix <prefix> [text]"


static func get_command_name() -> String:
	return "trim_prefix"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:1,max:2",
	})


func _execute(ctx:Context):
	var prefix = positional_args[0]
	return StrUtil.map_lines(ctx, StrUtil.inputs(ctx, positional_args, 1), func(s:String): return s.trim_prefix(prefix))

