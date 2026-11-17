extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Output the last N lines of stdin (default 10).
Usage: ... | tail [n]"

static func get_command_name() -> String:
	return "tail"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": "min:0,max:1",
	})

func _execute(ctx:Context):
	var n := 10
	if not positional_args.is_empty():
		# absi() so a Unix-style 'tail -1' behaves like 'tail 1' instead of
		# a negative count silently producing no output.
		n = absi(positional_args[0].to_int())
	var lines = ctx.stdin.split("\n", false)
	var start = max(0, lines.size() - n)
	for i in range(start, lines.size()):
		ctx.append_output(lines[i])

