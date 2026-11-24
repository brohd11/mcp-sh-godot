extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"



const _HELP = \
"Skip to the next iteration of the current loop. Only valid inside a gdsh loop."

static func get_command_name():
	return "continue"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
	})


func _execute(ctx:Context):
	for inh in ctx.get_inherited_ctxs():
		if inh.data.has("__is_loop__"):
			inh.data["__loop_continue__"] = true
			return ExitCode.OK

	ctx.append_error("Cannot continue when not in a loop.")
	return ExitCode.ERR

