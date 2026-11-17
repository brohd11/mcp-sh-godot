extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Print the contents of a text file to stdout.
Path is taken from the argument or from stdin.
Usage: cat [res://path]"

static func get_command_name() -> String:
	return "cat"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": "min:0,max:1",
		&"allow_positional_paths": true,
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
	if not FileAccess.file_exists(path):
		ctx.append_error("File does not exist: " + path)
		return ExitCode.FAIL

	var text = FileAccess.get_file_as_string(path)
	var err = FileAccess.get_open_error()
	if err != OK:
		ctx.append_error("Could not read file (error %s): %s" % [err, path])
		return ExitCode.FAIL
	ctx.append_output(text)

