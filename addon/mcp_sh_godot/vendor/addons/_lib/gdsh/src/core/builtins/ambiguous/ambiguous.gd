extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"
## Reached when a bare name is both a registered global class and a node under `cwn`.
## Context.get_scope runs during completion and highlighting, so it must stay side-effect free
## and cannot report the clash itself; it routes here instead and the error surfaces on execution.

const _HELP = "Internal: a bare name matched both a global class and a node."


static func get_command_name():
	return "__ambiguous__"


static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		# Trailing arguments are whatever the user meant to run; accept and ignore them.
		&"positional_count": "min:0",
	})


func _execute(ctx:Context):
	var name = consumed_tokens.front() if not consumed_tokens.is_empty() else "the name"
	ctx.append_error("'%s' is both a global class and a node; use 'script %s' or 'node %s'." % [name, name, name])
	return ExitCode.ERR

