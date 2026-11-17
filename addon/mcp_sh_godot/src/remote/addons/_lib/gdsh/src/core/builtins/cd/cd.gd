extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"


const _HELP = \
"Change the GDSh context working directory.
Usage: cd <rel or abs path>"

static func get_command_name():
	return "cd"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": 1,
	})

func _get_completions(completion:Completion) -> Dictionary:
	return get_completion_static(completion.context, positional_args)

static func get_completion_static(ctx:Context, pos_args:Array) -> Dictionary:
	var rel_path = ""
	if pos_args.size() > 0:
		rel_path = pos_args[0]
	return _completion_rel_path(ctx, rel_path)


func _execute(ctx:Context):
	return execute_static(ctx, positional_args)


static func execute_static(ctx:Context, pos_args:Array):
	var current_cwd = ctx.cwd
	var target = pos_args[0]

	target = _complete_path(target, ctx.cwd)

	target = target.simplify_path()
	if DirAccess.dir_exists_absolute(target):
		ctx.propogate(Context.Propagate.PROPERTY, "cwd", target)
	else:
		ctx.append_error("Directory does not exist: " + target)
		return ExitCode.ERR

