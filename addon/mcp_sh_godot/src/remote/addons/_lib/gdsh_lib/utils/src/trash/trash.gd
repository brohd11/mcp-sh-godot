extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Move files/directories to the OS trash (recoverable). Desktop platforms only.
Paths come from arguments and/or stdin (one per line).
Usage: trash [res://path ...]"

static func get_command_name() -> String:
	return "trash"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"allow_positional_paths": true,
	})

func _get_target_positional_count() -> int:
	return positional_args.size()

func _execute(ctx:Context):
	var paths := []
	for p in positional_args:
		paths.append(_complete_path(p, ctx.cwd))
	if ctx.stdin.strip_edges() != "":
		for line in ctx.stdin.split("\n", false):
			var p = line.strip_edges()
			if p != "":
				paths.append(_complete_path(p, ctx.cwd))

	if paths.is_empty():
		ctx.append_error("No paths to trash (argument or stdin).")
		return ExitCode.FAIL

	var count := 0
	for path in paths:
		if not (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)):
			ctx.append_error("Path does not exist: " + path)
			continue
		var err = OS.move_to_trash(ProjectSettings.globalize_path(path))
		if err != OK:
			ctx.append_error("Could not trash (error %s): %s" % [err, path])
			continue
		count += 1

	if count > 0:
		Utils.filesystem_changed(ctx)
	ctx.append_output("Moved %s item(s) to trash." % count)

