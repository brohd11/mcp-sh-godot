extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const NodePaths = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/node_paths.gd")


const _HELP = \
"Print the edited scene root's path (/scene), to start a 'tree' command chain.
Usage: editor scene root | tree nodes --recursive"

static func get_command_name():
	return "root"

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
	})

func _execute(ctx:Context):
	var edited_root = EditorInterface.get_edited_scene_root()
	if not is_instance_valid(edited_root):
		ctx.append_error("No edited scene open.")
		return ExitCode.FAIL
	ctx.append_output(NodePaths.path_of(edited_root))
	return ExitCode.OK

