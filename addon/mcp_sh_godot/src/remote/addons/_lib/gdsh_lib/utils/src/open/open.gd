extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Reveal a project directory in the OS file manager. Desktop platforms only.
Usage: open [{path:ctx.cwd}]"

static func get_command_name() -> String:
	return "open"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": "min:0,max:1",
		&"allow_positional_paths": true,
	})

func _execute(ctx:Context):
	var dir := ctx.cwd
	if not positional_args.is_empty():
		dir = _complete_path(positional_args[0], ctx.cwd)
	var globalized := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(globalized) and not FileAccess.file_exists(globalized):
		ctx.append_error("Path does not exist: " + dir)
		return ExitCode.FAIL
	OS.shell_show_in_file_manager(globalized)

