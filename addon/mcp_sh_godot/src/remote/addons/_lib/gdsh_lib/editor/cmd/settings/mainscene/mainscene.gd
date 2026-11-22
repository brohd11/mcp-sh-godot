extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _SETTING = "application/run/main_scene"

const _HELP = \
"Get or set the project's main scene.
Usage: settings mainscene [res://scene.tscn]
  (no arg)   print the current main scene path (pipe into 'open')
  <path>     set it and save project.godot"

static func get_command_name() -> String:
	return "mainscene"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:0,max:1",
	})

func _execute(ctx:Context):
	if positional_args.is_empty():
		var current = ProjectSettings.get_setting(_SETTING, "")
		if current == "":
			ctx.append_error("No main scene set.")
			return ExitCode.FAIL
		ctx.append_output(current)
		return ExitCode.OK

	var path = positional_args[0]
	if not FileAccess.file_exists(path):
		ctx.append_error("Scene does not exist: " + path)
		return ExitCode.FAIL
	ProjectSettings.set_setting(_SETTING, path)
	var err = ProjectSettings.save()
	if err != OK:
		ctx.append_error("project.godot save failed (error %s)." % err)
		return ExitCode.FAIL
	ctx.append_output("Main scene set to: " + path)
	return ExitCode.OK

