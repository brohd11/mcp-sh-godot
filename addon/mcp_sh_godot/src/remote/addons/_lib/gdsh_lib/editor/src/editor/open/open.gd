extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Open a scene, script or resource in the editor.
Path is taken from the argument or from stdin.
Usage: editor open [res://path] [--inspect]"

var inspect_flag := false

static func get_command_name() -> String:
	return "open"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:0,max:1",
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--inspect", {
		&"help": "Open the resource in the inspector as well."
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--inspect":
		inspect_flag = true

func _execute(ctx:Context):
	var path := ""
	if not positional_args.is_empty():
		path = positional_args[0]
	elif ctx.stdin.strip_edges() != "":
		# take the first non-empty line from stdin
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

	var ext := path.get_extension().to_lower()
	if ext == "tscn" or ext == "scn":
		EditorInterface.open_scene_from_path(path)
		ctx.append_output("Opened scene: " + path)
		return

	var res = load(path)
	if not is_instance_valid(res):
		ctx.append_error("Could not load resource: " + path)
		return ExitCode.FAIL

	if res is Script:
		EditorInterface.edit_script(res)
	else:
		EditorInterface.edit_resource(res)

	if inspect_flag:
		EditorInterface.edit_resource(res)
	ctx.append_output("Opened: " + path)

