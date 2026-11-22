extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"
const Execution = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/execute.gd")


const _HELP = \
"Run script in the current process."

static func get_command_name():
	return "source"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": 1,
		&"allow_positional_paths": true,
	})

func _execute(ctx:Context):
	var path = _complete_path(positional_args[0], ctx.cwd)
	if not FileAccess.file_exists(path):
		ctx.exit_code = ExitCode.FAIL
		ctx.append_error("File doesn't exist, cannot source: " + path)
		return ctx.exit_code
	var source_history = ctx.data.get_or_add("source_history", {})
	if source_history.has(path):
		return ctx.exit_code
	source_history[path] = true
	await Execution.source_file(path, ctx)
	return ctx.exit_code


