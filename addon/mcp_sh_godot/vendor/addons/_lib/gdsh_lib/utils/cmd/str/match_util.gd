extends RefCounted
## Shared body of the str predicates: print the inputs that match, or with --bool only set the
## exit code. Each command extends CommandBase itself (a user command can't share a base), keeps
## an instance of this, and passes its predicate. The command is duck-typed; no gdsh preload.

const StrUtil = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/utils/cmd/str/str_util.gd")

var bool_flag := false
var ignore_case_flag := false


## Adds --bool and --ignore-case to a command's Options.
static func add_flags(options) -> void:
	options.add_option("--bool", {&"short": "b", &"help": "Print nothing; exit 0 if any input matches."})
	options.add_option("--ignore-case", {&"short": "i", &"help": "Case-insensitive match."})


func process_flag(flag:String) -> void:
	if flag == "--bool":
		bool_flag = true
	elif flag == "--ignore-case":
		ignore_case_flag = true


## matches(text, needle) -> bool; both are already lowercased under --ignore-case.
func execute(cmd, ctx, matches:Callable) -> int:
	var args:Array[String] = cmd.positional_args
	var needle = args[0].to_lower() if ignore_case_flag else args[0]
	var lines = StrUtil.inputs(ctx, args, 1)
	var pred = func(line:String): return matches.call(line.to_lower() if ignore_case_flag else line, needle)
	return StrUtil.filter_lines(ctx, lines, pred, bool_flag)

