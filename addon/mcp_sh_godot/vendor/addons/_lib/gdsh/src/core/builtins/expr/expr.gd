extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"


const _HELP = \
"Run expression through Godot's Expression class.
Engine singletons (Engine, OS, ClassDB, ...) and method calls are available,
e.g. expr Engine.get_version_info(). Note: '()' is a subshell in the console language, so wrap
method calls in quotes if they don't return, e.g. expr \"OS.get_name()\".
Accepts arguments as 1 string or seperated."

static func get_command_name():
	return "expr"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": "min:1"
	})

func _execute(ctx:Context):
	run_expr(ctx, positional_args)
	return ctx.exit_code

static func run_expr(ctx:Context, args:Array):
	var expression = " ".join(args)
	var singletons = _get_singletons()
	var input_names = PackedStringArray(singletons.keys())
	var inputs = singletons.values()

	var expr = Expression.new()
	var err = expr.parse(expression, input_names)
	if err != OK:
		ctx.append_error("Could not parse expression: %s" % expr.get_error_text())
		ctx.exit_code = ExitCode.ERR
		return

	# base_instance = null; const_calls_only = false so method calls on singletons work.
	var val = expr.execute(inputs, null, false, false)
	if expr.has_execute_failed():
		ctx.append_error("Could not execute expression: %s" % expr.get_error_text())
		ctx.exit_code = ExitCode.ERR
		return

	ctx.append_output(str(val))

# Engine singletons exposed as named inputs to the Expression. A curated set (available at runtime) is merged with whatever Engine.get_singleton_list() reports.
static func _get_singletons() -> Dictionary:
	var d := {
		"Engine": Engine,
		"OS": OS,
		"Time": Time,
		"Input": Input,
		"InputMap": InputMap,
		"ClassDB": ClassDB,
		"ProjectSettings": ProjectSettings,
		"DisplayServer": DisplayServer,
		"RenderingServer": RenderingServer,
	}
	for n in Engine.get_singleton_list():
		if not d.has(n):
			d[n] = Engine.get_singleton(n)
	return d

