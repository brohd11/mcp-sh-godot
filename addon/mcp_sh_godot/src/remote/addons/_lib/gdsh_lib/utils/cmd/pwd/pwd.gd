extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"


const _HELP = \
"Print current working directory.
Usage: pwd [--local]"

var local_flag:=false

static func get_command_name():
	return "pwd"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--local", {
		&"short": "l",
		&"help": "Attempt local conversion to path"
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--local":
		local_flag = true

func _execute(ctx:Context):
	var p = ctx.cwd
	if local_flag:
		p = ProjectSettings.localize_path(p)
	else:
		p = ProjectSettings.globalize_path(p)
	ctx.append_output(p)
	return ExitCode.OK

