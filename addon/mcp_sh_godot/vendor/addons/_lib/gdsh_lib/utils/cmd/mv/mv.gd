extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Move or rename a file/directory in the project.
NOTE: this does not rewrite references to the moved resource.
Usage: mv <res://src> <res://dest>"

static func get_command_name() -> String:
	return "mv"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": 2,
		&"allow_positional_paths": true,
	})

func _execute(ctx:Context):
	var src = _complete_path(positional_args[0], ctx.cwd)
	var dest = _complete_path(positional_args[1], ctx.cwd)

	if not (FileAccess.file_exists(src) or DirAccess.dir_exists_absolute(src)):
		ctx.append_error("Source does not exist: " + src)
		return ExitCode.FAIL
	if FileAccess.file_exists(dest) or DirAccess.dir_exists_absolute(dest):
		ctx.append_error("Destination already exists: " + dest)
		return ExitCode.FAIL

	var dest_dir = dest.get_base_dir()
	if not DirAccess.dir_exists_absolute(dest_dir):
		DirAccess.make_dir_recursive_absolute(dest_dir)

	var err = DirAccess.rename_absolute(src, dest)
	if err != OK:
		ctx.append_error("mv failed (error %s): %s -> %s" % [err, src, dest])
		return ExitCode.FAIL
	Utils.filesystem_changed(ctx)
	ctx.append_output(dest)
	return ExitCode.OK

