extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const TargetUtil = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/target_util.gd")

const _HELP = \
"Print a script's resource path or a live node's absolute path.
Usage: script <target> get_path
Usage: node <path> get_path"

static func get_command_name():
	return "get_path"

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
	})

func _execute(ctx:Context):
	var script = TargetUtil.get_target(ctx)
	if not is_instance_valid(script):
		ctx.append_error(TargetUtil.target_error(ctx))
		return ExitCode.FAIL
	if script is Node:
		ctx.append_output(str(script.get_path()))
	elif script.resource_path == "":
		# Inner classes, and scripts built from a file outside the project, have no path.
		ctx.append_output("No Path - Likely Inner Class")
	else:
		ctx.append_output(script.resource_path)
	return ExitCode.OK

