extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const StrUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/str/str_util.gd")

const _HELP = \
"Replace every occurrence of a substring (String.replace).
Usage: str replace [-i] <from> <to> [text]"

var ignore_case_flag := false


static func get_command_name() -> String:
	return "replace"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:2,max:3",
	})


func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--ignore-case", {&"short": "i", &"help": "Case-insensitive match (String.replacen)."})
	return options.get_options()


func _process_flag(flag:String):
	if flag == "--ignore-case":
		ignore_case_flag = true


func _execute(ctx:Context):
	var from = positional_args[0]
	var to = positional_args[1]
	var fn = func(s:String): return s.replacen(from, to) if ignore_case_flag else s.replace(from, to)
	return StrUtil.map_lines(ctx, StrUtil.inputs(ctx, positional_args, 2), fn)

