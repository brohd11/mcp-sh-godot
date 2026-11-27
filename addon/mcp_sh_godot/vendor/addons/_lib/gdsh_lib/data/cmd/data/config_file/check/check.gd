extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const ConfigData = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/data/src/config_data.gd")

const _HELP = \
"Check that ConfigFiles load: prints `ok: <file>` for each, or why it failed (with the line).
Usage: data config_file check <file>..., or file paths one per stdin line."

static func get_command_name():
	return "check"

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:0",
		&"allow_positional_paths": true,
	})

func _execute(ctx:Context):
	var inputs = positional_args if not positional_args.is_empty() else Array(ctx.stdin.split("\n", false))
	if inputs.is_empty():
		ctx.append_error("Need a config file path (argument or stdin).")
		return ExitCode.ERR
	var status = ExitCode.OK
	for input in inputs:
		var path = complete_path(input.strip_edges())
		var loaded = ConfigData.load_cfg(self, path)
		if loaded.has("error"):
			ctx.append_error(loaded.error)
			status = ExitCode.FAIL
		else:
			ctx.append_output("ok: " + path)
	return status

