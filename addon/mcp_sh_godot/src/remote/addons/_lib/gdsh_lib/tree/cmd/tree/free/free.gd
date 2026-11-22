extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const TreeUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/tree_util.gd")

const _HELP = \
"Remove the stdin nodes from the tree (undoable when the host provides undo, otherwise freed).
The SceneTree root is never freed.
Usage: ... | tree free"


static func get_command_name() -> String:
	return "free"


static func get_self_command_data() -> Dictionary:
	return _command_data({&"help": _HELP})


func _execute(ctx:Context):
	var nodes = TreeUtil.resolve_targets(ctx)
	if nodes.is_empty():
		return ExitCode.FAIL

	var tree_root = TreeUtil.get_tree_root()
	var targets := []
	for n:Node in nodes:
		if n == tree_root:
			ctx.append_error("Refusing to free the SceneTree root.")
			continue
		# A descendant of another target goes with it; removing both would break undo order.
		var nested = nodes.any(func(other): return other != n and other.is_ancestor_of(n))
		if not nested and not n in targets:
			targets.append(n)
	if targets.is_empty():
		ctx.append_error("No target nodes to free.")
		return ExitCode.FAIL

	var a = TreeUtil.action(ctx, "Free %s node(s)" % targets.size())
	for n:Node in targets:
		var parent = n.get_parent()
		a.do_method(parent, &"remove_child", [n])
		a.undo_method(parent, &"add_child", [n])
		a.undo_method(parent, &"move_child", [n, n.get_index()])
		a.undo_method(n, &"set_owner", [n.owner])
		a.undo_reference(n)
	a.commit()

	ctx.append_output("Freed %s node(s)." % targets.size())
	return ExitCode.OK

