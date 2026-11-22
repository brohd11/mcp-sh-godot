extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Reveal a path in the FileSystem dock.
Path is taken from the argument or from stdin.
Usage: editor reveal [res://path]"

static func get_command_name() -> String:
	return "reveal"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:0,max:1",
	})

func _execute(ctx:Context):
	var path := ""
	if not positional_args.is_empty():
		path = positional_args[0]
	elif ctx.stdin.strip_edges() != "":
		for line in ctx.stdin.split("\n", false):
			if line.strip_edges() != "":
				path = line.strip_edges()
				break

	if path == "":
		ctx.append_error("No path provided (argument or stdin).")
		return ExitCode.FAIL
	path = _complete_path(path, ctx.cwd)
	if not (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)):
		ctx.append_error("Path does not exist: " + path)
		return ExitCode.FAIL

	var dock = EditorInterface.get_file_system_dock()
	if not is_instance_valid(dock):
		ctx.append_error("Could not access the FileSystem dock.")
		return ExitCode.FAIL
	dock.navigate_to_path(path)
	ctx.append_output("Revealed: " + path)
	return ExitCode.OK

