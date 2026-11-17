extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Run the project.
Usage: editor play [--current] [--scene=res://path.tscn]
  (no flags)   run the main scene"

var current_flag := false
var scene_flag := ""

static func get_command_name() -> String:
	return "play"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--current", {
		&"help": "Run the currently edited scene."
	})
	options.add_option("--scene=", {
		&"help": "Run a specific scene file.",
		&"trailing_char": "",
		&"flag_completion": {"type": FlagType.FILE, "ext": ["tscn", "scn"]},
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--current":
		current_flag = true
	elif flag.begins_with("--scene="):
		scene_flag = _get_flag_value(flag)

func _execute(ctx:Context):
	if scene_flag != "":
		if not FileAccess.file_exists(scene_flag):
			ctx.append_error("Scene does not exist: " + scene_flag)
			return ExitCode.FAIL
		EditorInterface.play_custom_scene(scene_flag)
		ctx.append_output("Playing scene: " + scene_flag)
	elif current_flag:
		EditorInterface.play_current_scene()
		ctx.append_output("Playing current scene.")
	else:
		EditorInterface.play_main_scene()
		ctx.append_output("Playing main scene.")

