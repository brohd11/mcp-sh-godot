extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const StrUtil = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/utils/cmd/str/str_util.gd")

const _HELP = \
"Strip whitespace from both ends of each input (String.strip_edges).
Usage: str strip_edges [--left] [--right] [text]"

var left_flag := false
var right_flag := false


static func get_command_name() -> String:
	return "strip_edges"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:0,max:1",
	})


func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--left", {&"short": "l", &"help": "Strip leading whitespace only."})
	options.add_option("--right", {&"short": "r", &"help": "Strip trailing whitespace only."})
	return options.get_options()


func _process_flag(flag:String):
	if flag == "--left":
		left_flag = true
	elif flag == "--right":
		right_flag = true


func _execute(ctx:Context):
	# Neither flag strips both ends.
	var left = left_flag or not right_flag
	var right = right_flag or not left_flag
	return StrUtil.map_lines(ctx, StrUtil.inputs(ctx, positional_args, 0), func(s:String): return s.strip_edges(left, right))

