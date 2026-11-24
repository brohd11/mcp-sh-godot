extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Count stdin lines (default), words, or characters.
Usage: ... | count [--words] [--chars]"

var words_flag := false
var chars_flag := false

static func get_command_name() -> String:
	return "count"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--words", {&"short": "w", &"help": "Count whitespace-separated words."})
	options.add_option("--chars", {&"short": "c", &"help": "Count characters."})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--words":
		words_flag = true
	elif flag == "--chars":
		chars_flag = true

func _execute(ctx:Context):
	if chars_flag:
		ctx.append_output(str(ctx.stdin.strip_edges().length()))
	elif words_flag:
		var text = ctx.stdin.strip_edges().replace("\t", " ").replace("\n", " ")
		ctx.append_output(str(text.split(" ", false).size() if text != "" else 0))
	else:
		ctx.append_output(str(ctx.stdin.split("\n", false).size()))
	return ExitCode.OK

