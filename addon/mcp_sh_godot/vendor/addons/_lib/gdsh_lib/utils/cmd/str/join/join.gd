extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const StrUtil = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/utils/cmd/str/str_util.gd")

const _HELP = \
"Append a path segment (String.path_join).
Usage: str join <part> [text]"


static func get_command_name() -> String:
	return "join"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:1,max:2",
	})


func _execute(ctx:Context):
	var part = positional_args[0]
	return StrUtil.map_lines(ctx, StrUtil.inputs(ctx, positional_args, 1), func(s:String): return s.path_join(part))

