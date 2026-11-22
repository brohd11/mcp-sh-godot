extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Get or set a project setting (ProjectSettings).
Usage: settings psetting <name> [value]
  (no value)   print the current value
  <value>      set it (converted to the setting's current type) and save project.godot"

static func get_command_name() -> String:
	return "psetting"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:1,max:2",
	})

func _execute(ctx:Context):
	var name = positional_args[0]

	if positional_args.size() == 1:
		if not ProjectSettings.has_setting(name):
			ctx.append_error("No such project setting: " + name)
			return ExitCode.FAIL
		ctx.append_output(str(ProjectSettings.get_setting(name)))
		return ExitCode.OK

	var new_val = positional_args[1]
	var current = ProjectSettings.get_setting(name)
	var converted = null
	if new_val == "null":
		ctx.append_output("null erases setting: %s -> null" % [current])
	else:
		converted = Utils_Value.convert(new_val, typeof(current))
		if converted == null:
			ctx.append_error("Could not convert: %s -> %s" % [new_val, typeof(current)])
			return ExitCode.ERR
	
	ProjectSettings.set_setting(name, converted)
	var err = ProjectSettings.save()
	if err != OK:
		ctx.append_error("Saved setting but project.godot save failed (error %s)." % err)
		return ExitCode.FAIL
	ctx.append_output("%s = %s" % [name, str(converted)])
	return ExitCode.OK

