extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"
## Clear the attached console. The host supplies `ctx.host_data["clear_callback"]`:
## `Callable(ctx:Context, history:bool)`, optionally returning an exit status.
## GDSh.Console provides one for its own transcript and history.

const _HELP = \
"Clear the console output.
Usage: clear [--history]"

var clear_history_flag := false


static func get_command_name() -> String:
	return "clear"


static func get_self_command_data() -> Dictionary:
	return _command_data({&"help": _HELP, &"discoverable": false})


func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--history", {&"help": "Also clear the prompt history."})
	return options.get_options()


func _process_flag(flag:String):
	if flag == "--history":
		clear_history_flag = true


func _execute(ctx:Context):
	var callback = ctx.host_data.get("clear_callback")
	if not (callback is Callable and callback.is_valid()):
		ctx.append_error("clear: no console is attached")
		return ExitCode.FAIL
	var status = callback.call(ctx, clear_history_flag)
	return status if status is int else ExitCode.OK

