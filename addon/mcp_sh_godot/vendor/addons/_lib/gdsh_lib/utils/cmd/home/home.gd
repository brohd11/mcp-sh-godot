extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"


const _HELP = \
"Print the user's home directory ($HOME, or $USERPROFILE on Windows).
Usage: home"

static func get_command_name():
	return "home"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
	})

func _execute(ctx:Context):
	var home = OS.get_environment("HOME")
	if home.is_empty():
		home = OS.get_environment("USERPROFILE")
	if home.is_empty() or not DirAccess.dir_exists_absolute(home):
		ctx.append_error("Home directory doesn't exist: " + home)
		return ExitCode.FAIL
	ctx.append_output(home)
	return ExitCode.OK

