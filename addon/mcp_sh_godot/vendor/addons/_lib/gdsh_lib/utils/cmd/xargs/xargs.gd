extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const Lexer = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/lexer.gd")
const Execution = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/execute.gd")

const _HELP = \
"Passes stdin words as arguments to the following command.
Everything from the command on is passed through, flags included. With -n N the
command runs once per N words instead of once with all of them:
  find \"*.gd\" | xargs -n 1 check
Usage: xargs [-n N|--max-args=N] <command> [args/flags...]"

var max_args := 0


static func get_command_name():
	return "xargs"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--max-args=", {&"help": "Words per run (also -n N)."})
	return options.get_options()

func _get_target_positional_count() -> int:
	return positional_args.size()

## Only leading options are xargs' own; the rest is moved to positional_args here so _route
## never parses the target command's flags as ours.
func _consume_self(ctx:Context) -> ExitCode:
	_consume_token(ctx)
	while not ctx.unconsumed_tokens.is_empty():
		var token:String = ctx.unconsumed_tokens[0]
		var count = null
		if token == "-n":
			_consume_token(ctx)
			count = _consume_token(ctx) if not ctx.unconsumed_tokens.is_empty() else ""
		elif token.begins_with("-n") and token.length() > 2:
			count = _consume_token(ctx).substr(2)
		elif token.begins_with("--max-args="):
			count = _get_flag_value(_consume_token(ctx))
		else:
			break
		if not count.is_valid_int() or count.to_int() < 1:
			ctx.append_error("xargs: -n needs a positive number, got '%s'" % count)
			return ExitCode.ERR
		max_args = count.to_int()
	# Help before the command is ours; after it, it belongs to the command.
	if not ctx.unconsumed_tokens.is_empty() and ctx.unconsumed_tokens[0] in ["-h", "--help"]:
		return ExitCode.OK
	while not ctx.unconsumed_tokens.is_empty():
		positional_args.append(_consume_token(ctx))
	return ExitCode.OK

func _execute(ctx:Context):
	# Quote-aware words keep their quotes, so the joined command reparses identically.
	# Operator tokens in stdin are dropped rather than becoming shell syntax.
	var words:Array[String] = []
	for token in Lexer.scan(ctx.stdin, true).tokens:
		if token.kind == "word":
			words.append(token.raw)
	if max_args <= 0 or words.size() <= max_args:
		return await _run(ctx, words)
	var status = ExitCode.OK
	for i in range(0, words.size(), max_args):
		var code = await _run(ctx, words.slice(i, i + max_args))
		if code != ExitCode.OK and status == ExitCode.OK:
			status = code
	return status

func _run(ctx:Context, words:Array[String]) -> int:
	var command = positional_args.duplicate()
	command.append_array(words)
	await Execution.execute_command(" ".join(command), {&"parent_ctx": ctx})
	return ctx.exit_code

