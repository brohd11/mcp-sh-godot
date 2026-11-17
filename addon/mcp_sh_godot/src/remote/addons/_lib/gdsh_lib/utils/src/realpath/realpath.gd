extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"


const _HELP = \
"Convert relative path to full path, globalized or local.
Usage: realpath [--global] [file path]"

var global_flag:=false

static func get_command_name():
	return "realpath"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": 1,
		&"allow_positional_paths": true
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--global", {
		&"short": "g",
		&"help": "Convert the path to globalized"
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--global":
		global_flag = true


func _execute(ctx:Context):
	var converted = complete_path(positional_args[0])
	if not (FileAccess.file_exists(converted) or DirAccess.dir_exists_absolute(converted)):
		ctx.append_output("No such file or directory")
		return ExitCode.FAIL
	
	if global_flag:
		converted = ProjectSettings.globalize_path(converted)
	else:
		converted = ProjectSettings.localize_path(converted)
	ctx.append_output(converted)

