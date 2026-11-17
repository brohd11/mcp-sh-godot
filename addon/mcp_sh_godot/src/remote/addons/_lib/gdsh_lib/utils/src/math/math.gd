extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"
const Expr = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/builtins/expr/expr.gd")

const _HELP = \
"Run expression through Godot's Expression class.
This is functionally an alias for 'expr' command.
Accepts arguments as 1 string or seperated."

static func get_command_name():
	return "math"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": "min:1"
	})

func _execute(ctx:Context):
	Expr.run_expr(ctx, positional_args)

