extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Reload the currently edited scene from disk, discarding unsaved changes.
Usage: editor scene reload"

static func get_command_name() -> String:
	return "reload"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
	})

func _execute(ctx:Context):
	var root = EditorInterface.get_edited_scene_root()
	if not is_instance_valid(root):
		ctx.append_error("No edited scene to reload.")
		return ExitCode.FAIL
	var path = root.scene_file_path
	if path == "":
		ctx.append_error("Edited scene has not been saved yet; nothing to reload from.")
		return ExitCode.FAIL
	EditorInterface.reload_scene_from_path(path)
	ctx.append_output("Reloaded scene: " + path)
	return ExitCode.OK

