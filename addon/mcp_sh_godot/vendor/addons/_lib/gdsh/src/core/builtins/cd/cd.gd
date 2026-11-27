extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"


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
	if ctx.has_filesystem():
		return PathCompletion.files(rel_path, ctx.cwd, rel_path, ctx, true)
	return _completion_rel_path(ctx, rel_path)


func _execute(ctx:Context):
	return execute_static(ctx, positional_args)


static func execute_static(ctx:Context, pos_args:Array):
	var current_cwd = ctx.cwd
	var target = pos_args[0]
	if ctx.has_filesystem():
		var listing = ctx.list_directory(target)
		if not listing.ok:
			ctx.append_error(listing.message)
			return ExitCode.ERR
		ctx.propogate(Context.Propagate.PROPERTY, "cwd", listing.path)
		return ExitCode.OK

	target = _complete_path(target, ctx.cwd)

	target = target.simplify_path()
	if DirAccess.dir_exists_absolute(target):
		ctx.propogate(Context.Propagate.PROPERTY, "cwd", target)
	else:
		ctx.append_error("Directory does not exist: " + target)
		return ExitCode.ERR
	return ExitCode.OK

