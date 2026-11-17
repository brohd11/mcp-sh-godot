extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"


const _HELP = \
"Print the edited scene root's absolute node path, to start a 'tree' command chain.
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
	ctx.append_output(str(edited_root.get_path()))
	return ExitCode.OK

