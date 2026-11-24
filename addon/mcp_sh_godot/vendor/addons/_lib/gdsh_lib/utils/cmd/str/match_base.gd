extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"
## Base for str predicates: print the inputs that match, or with --bool only set the exit
## code. Subclasses implement _matches.

const StrUtil = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/utils/cmd/str/str_util.gd")

var bool_flag := false
var ignore_case_flag := false


func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--bool", {&"short": "b", &"help": "Print nothing; exit 0 if any input matches."})
	options.add_option("--ignore-case", {&"short": "i", &"help": "Case-insensitive match."})
	return options.get_options()


func _process_flag(flag:String):
	if flag == "--bool":
		bool_flag = true
	elif flag == "--ignore-case":
		ignore_case_flag = true


func _execute(ctx:Context):
	var needle = positional_args[0].to_lower() if ignore_case_flag else positional_args[0]
	var lines = StrUtil.inputs(ctx, positional_args, 1)
	var pred = func(line:String): return _matches(line.to_lower() if ignore_case_flag else line, needle)
	return StrUtil.filter_lines(ctx, lines, pred, bool_flag)


## Whether text matches needle; both are already lowercased under --ignore-case.
func _matches(_text:String, _needle:String) -> bool:
	return false

