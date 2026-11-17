extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Await a timer, then report the elapsed time. Exercises async command execution.
Usage: wait <seconds> [label]"

static func get_command_name():
	return "wait"

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:1,max:2",
		&"discoverable": false,
	})

func _execute(ctx:Context):
	var start = Time.get_ticks_msec()
	var frames = Engine.get_process_frames()
	await (Engine.get_main_loop() as SceneTree).create_timer(positional_args[0].to_float()).timeout
	var label = positional_args[1] if positional_args.size() > 1 else "waited"
	ctx.append_output("%s: %d ms, %d frames" % [label, Time.get_ticks_msec() - start, Engine.get_process_frames() - frames])
	return ExitCode.OK

