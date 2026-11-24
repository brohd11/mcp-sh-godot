extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Restart the Godot editor.
Usage: editor restart [--no-save]"

var no_save_flag := false

static func get_command_name() -> String:
	return "restart"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--no-save", {&"help": "Restart without saving open scenes first."})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--no-save":
		no_save_flag = true

func _execute(ctx:Context):
	var save := not no_save_flag
	ctx.append_output("Restarting editor (%s open scenes)..." % ("saving" if save else "discarding unsaved changes in"))
	EditorInterface.restart_editor(save)
	return ExitCode.OK

