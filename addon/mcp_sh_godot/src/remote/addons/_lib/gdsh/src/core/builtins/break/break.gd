extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"


const _HELP = \
"Break out of the current loop. Only valid inside a gdsh loop."

static func get_command_name():
	return "break"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
	})

func _execute(ctx:Context):
	for inh in ctx.get_inherited_ctxs():
		if inh.data.has("__is_loop__"):
			inh.data["__loop_break__"] = true
			return

	ctx.append_error("Cannot break when not in a loop.")
	ctx.exit_code = ExitCode.ERR

