extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"
const Execution = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/execute.gd")


const _HELP = \
"Run a .gdsh script in a subshell, with its own $0, $1 and $#.
Session state does not leak back out; use `source` to run a script in the current scope.
Usage:
  gdsh <path.gdsh> [args...]
  <path.gdsh> [args...]      the same, with the path in command position"

var script_path:String

static func get_command_name():
	return "gdsh"

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:0",
	})

## Entered explicitly as `gdsh <path>`, or with the path itself in command position.
func _consume_self(ctx:Context) -> ExitCode:
	var token = _consume_token(ctx)
	if token == get_command_name():
		# Nothing to run: fall through to _execute, which prints help.
		if ctx.tokens_empty() or ctx.unconsumed_tokens.front().begins_with("-"):
			return ExitCode.OK
		token = _consume_token(ctx)
	script_path = _complete_path(Utils.unquote(token), ctx.cwd)
	return ExitCode.OK

func _execute(ctx:Context):
	if script_path.is_empty():
		ctx.append_output(get_help_string(true))
		return ExitCode.OK
	# The extension is the only gate: a .gdsh file needs no #!gdsh tag.
	if script_path.get_extension().to_lower() != "gdsh":
		ctx.append_error("Not a .gdsh script: " + script_path)
		return ExitCode.FAIL
	if not FileAccess.file_exists(script_path):
		ctx.append_error("File doesn't exist: " + script_path)
		return ExitCode.FAIL
	var file_as_string = FileAccess.get_file_as_string(script_path)

	var sub_ctx = Context.new_ctx(script_path.get_file() + "-SubShell", ctx, true)
	sub_ctx.set_positional_args(script_path, positional_args)

	await Execution.execute_command_multiline(file_as_string, sub_ctx)

	# Absorb rather than append: the sub-shell streamed its own output as it ran. Trimming here
	# instead of strip_*_newlines leaves its buffers intact, so what streamed still matches them.
	ctx.absorb_output(sub_ctx.stdout.trim_suffix("\n"))
	ctx.absorb_error(sub_ctx.stderr.trim_suffix("\n"))
	ctx.exit_code = sub_ctx.exit_code
	ctx.last_status = sub_ctx.exit_code

