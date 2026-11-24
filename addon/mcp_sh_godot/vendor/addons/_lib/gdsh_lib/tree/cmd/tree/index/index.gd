extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const TreeUtil = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/tree/src/tree_util.gd")

const _HELP = \
"Print the child index of each stdin node, or move the nodes to an index within their parent.
Usage: ... | tree index [index] [--first] [--last]"

var first_flag:bool = false
var last_flag:bool = false


static func get_command_name() -> String:
	return "index"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:0,max:1",
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--first", {&"help": "Move the node to the first index"})
	options.add_option("--last", {&"help": "Move the node to the last index."})
	return options.get_options()


func _execute(ctx:Context) -> int:
	var inputs = TreeUtil.resolve_targets(ctx)
	if inputs.is_empty():
		return ExitCode.FAIL

	if not positional_args.is_empty() and (first_flag or last_flag):
		ctx.append_error("Postional arg and flag provided, choose one.")
		return ExitCode.FAIL

	if first_flag and last_flag:
		first_flag = false
		ctx.append_output("Conflicting flags, defaulting to --last.")

	if positional_args.is_empty() and not (first_flag or last_flag):
		for node:Node in inputs:
			ctx.append_output(str(node.get_index()))
		return ExitCode.OK

	var target_i:int = 0
	if not positional_args.is_empty():
		if not positional_args[0].is_valid_int():
			ctx.append_error("Target index must be int: %s" % positional_args[0])
			return ExitCode.FAIL
		target_i = int(positional_args[0])

	var action = TreeUtil.action(ctx, "Set Node Index")
	var snapshots := {}
	var order = range(inputs.size()) if last_flag else range(inputs.size() - 1, -1, -1)
	var moved := 0
	for i:int in order:
		var node:Node = inputs[i]
		var n_par = node.get_parent()
		if n_par == null:
			ctx.append_error("Cannot reorder a node with no parent: %s" % TreeUtil.path_of(node))
			continue
		var count = n_par.get_child_count()
		var targ = 0 if first_flag else (count - 1 if last_flag else target_i)
		if targ < -count or targ >= count:
			_append_out(ctx, node, false)
			continue
		if not snapshots.has(n_par):
			snapshots[n_par] = n_par.get_children()
		action.do_method(n_par, &"move_child", [node, targ])
		_append_out(ctx, node, true)
		moved += 1

	for n_par:Node in snapshots:
		var children:Array = snapshots[n_par]
		for ci:int in children.size():
			action.undo_method(n_par, &"move_child", [children[ci], ci])

	action.commit()
	return ExitCode.OK if moved > 0 else ExitCode.FAIL

func _append_out(ctx:Context, node:Node, success:bool):
	if success:
		ctx.append_output("Moved Node: %s" % TreeUtil.path_of(node))
	else:
		ctx.append_output("Could not move Node: %s" % TreeUtil.path_of(node))

func _get_completions(completion:Completion):
	if last_flag or first_flag:
		return {}
	return super._get_completions(completion)

