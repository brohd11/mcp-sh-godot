extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Stop the running project.
Usage: editor stop"

static func get_command_name() -> String:
	return "stop"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
	})

func _execute(ctx:Context):
	if not EditorInterface.is_playing_scene():
		ctx.append_output("No scene is currently playing.")
		return ExitCode.OK
	EditorInterface.stop_playing_scene()
	ctx.append_output("Stopped playing scene.")
	return ExitCode.OK

