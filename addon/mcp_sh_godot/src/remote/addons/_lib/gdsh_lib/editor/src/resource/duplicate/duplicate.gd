extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Duplicate a resource file to a new path.
Usage: resource duplicate <res://src> <res://dest> [--subresources]
The destination path is written to stdout (pipe into 'open')."

var subresources_flag := false

static func get_command_name() -> String:
	return "duplicate"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": 2,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--subresources", {
		&"help": "Deep-duplicate sub-resources."
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--subresources":
		subresources_flag = true

func _execute(ctx:Context):
	var src = positional_args[0]
	var dest = positional_args[1]

	if not FileAccess.file_exists(src):
		ctx.append_error("Source does not exist: " + src)
		return ExitCode.FAIL

	var res = load(src)
	if not res is Resource:
		ctx.append_error("Source is not a resource: " + src)
		return ExitCode.FAIL

	var copy = res.duplicate(subresources_flag)
	var err = ResourceSaver.save(copy, dest)
	if err != OK:
		ctx.append_error("Save failed (error %s): %s" % [err, error_string(err)])
		return ExitCode.FAIL

	EditorInterface.get_resource_filesystem().update_file(dest)
	ctx.append_output(dest)

