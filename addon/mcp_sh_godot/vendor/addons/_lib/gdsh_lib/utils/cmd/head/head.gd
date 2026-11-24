extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Output the first N lines of stdin (default 10).
Usage: ... | head [n]"

static func get_command_name() -> String:
	return "head"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": "min:0,max:1",
	})

func _execute(ctx:Context):
	var n := 10
	if not positional_args.is_empty():
		# absi() so a Unix-style 'head -1' behaves like 'head 1' instead of
		# a negative count silently producing no output.
		n = absi(positional_args[0].to_int())
	var lines = ctx.stdin.split("\n", false)
	for i in range(min(n, lines.size())):
		ctx.append_output(lines[i])
	return ExitCode.OK

