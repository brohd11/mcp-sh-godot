extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const NodePaths = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/node_paths.gd")

const _HELP = \
"Change the GDSh working node, the base for relative node paths (as cd is for file paths).
Usage: cn [--internal|-i] <rel or abs node path>"

var internal_flag := false

static func get_command_name():
	return "cn"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": 1,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--internal", {
		&"short": "i",
		&"help": "Include internal children in node-path completion.",
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--internal":
		internal_flag = true

func _get_completions(completion:Completion) -> Dictionary:
	var has_space = completion.char_before_cursor in [" ", "\t", "\n", ""]
	if not has_space and completion.token_before_cursor.begins_with("-"):
		return get_flags(true)
	if not _positional_arg_index_valid():
		return get_flags(true) if has_space else {}
	var path = str(positional_args[0]) if not positional_args.is_empty() else ""
	var choices = NodePaths.complete_path(path, completion.context.cwn, completion.token_before_cursor, internal_flag)
	if has_space:
		choices.merge(get_flags(true))
	return choices

static func get_completion_static(ctx:Context, pos_args:Array, include_internal:bool=false) -> Dictionary:
	var rel_path = ""
	if pos_args.size() > 0:
		rel_path = pos_args[0]
	return NodePaths.complete_path(rel_path, ctx.cwn, "", include_internal)


func _execute(ctx:Context):
	return execute_static(ctx, positional_args)


static func execute_static(ctx:Context, pos_args:Array):
	var target = pos_args[0]
	var node = NodePaths.resolve(target, ctx.cwn)
	if node == null:
		ctx.append_error("Node does not exist: " + target)
		return ExitCode.ERR
	# Stored absolute, so a later cwd/scene change cannot re-anchor a relative value.
	ctx.propogate(Context.Propagate.PROPERTY, "cwn", NodePaths.path_of(node))
	return ExitCode.OK

