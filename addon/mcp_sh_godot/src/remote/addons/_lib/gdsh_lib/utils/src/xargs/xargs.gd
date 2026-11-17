extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const Lexer = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/lexer.gd")
const Execution = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/execute.gd")

const _HELP = \
"Passes stdin as arguments to the following command(s).
Usage: xargs command --flags (stdin goes here)"

static func get_command_name():
	return "xargs"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
	})

func _get_target_positional_count() -> int:
	return positional_args.size()

func _execute(ctx:Context):
	# Quote-aware words keep their quotes, so the joined command reparses identically.
	# Operator tokens in stdin are dropped rather than becoming shell syntax.
	var split_stdin:Array[String] = []
	for token in Lexer.scan(ctx.stdin, true).tokens:
		if token.kind == "word":
			split_stdin.append(token.raw)
	positional_args.append_array(split_stdin)
	var new_command = " ".join(positional_args)
	await Execution.execute_command(new_command, {
		&"parent_ctx": ctx
	})
	

