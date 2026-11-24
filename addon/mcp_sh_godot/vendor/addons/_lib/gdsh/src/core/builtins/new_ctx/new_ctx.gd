extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"
## Reset the attached console's session. The host supplies `ctx.host_data["new_ctx_callback"]`:
## `Callable(ctx:Context)`, optionally returning an exit status. GDSh.Console provides one that
## rebuilds its context once the submission finishes. Like `exit`, the rest of the submission stops.

const _HELP = \
"Reset the console session (variables, functions, aliases, cwd).
Usage: new_ctx"


static func get_command_name() -> String:
	return "new_ctx"


static func get_self_command_data() -> Dictionary:
	return _command_data({&"help": _HELP, &"discoverable": false})


func _execute(ctx:Context):
	var callback = ctx.host_data.get("new_ctx_callback")
	if not (callback is Callable and callback.is_valid()):
		ctx.append_error("new_ctx: no console is attached")
		return ExitCode.FAIL
	var status = callback.call(ctx)
	if not status is int: status = ExitCode.OK
	# Nothing else should run against a session that is about to be replaced.
	for inh in [ctx] + ctx.get_inherited_ctxs():
		inh.exit_requested = true
		inh.exit_code = status
	return status

