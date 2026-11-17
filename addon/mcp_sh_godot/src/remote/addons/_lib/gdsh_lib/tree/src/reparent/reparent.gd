extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const TreeUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/tree_util.gd")
const NodePaths = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/node_paths.gd")

const _HELP = \
"Move the stdin nodes under a new parent (keeps global transform) and print their new absolute paths.
The moved nodes join the new parent's scene.
Usage: ... | tree reparent </absolute/parent/path>"


static func get_command_name() -> String:
	return "reparent"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": 1,
	})


func _execute(ctx:Context):
	var target_path = positional_args[0]
	if not NodePath(target_path).is_absolute():
		ctx.append_error("Not an absolute node path: " + target_path)
		return ExitCode.FAIL
	var tree_root = TreeUtil.get_tree_root()
	var target = NodePaths.resolve(target_path)
	if not is_instance_valid(target):
		ctx.append_error("Parent node not found: " + target_path)
		return ExitCode.FAIL

	var nodes = TreeUtil.resolve_targets(ctx)
	if nodes.is_empty():
		return ExitCode.FAIL

	var a = TreeUtil.action(ctx, "Reparent under %s" % target.name)
	var moved := []
	for n:Node in nodes:
		if n == tree_root:
			ctx.append_error("Cannot reparent the SceneTree root.")
			continue
		if n == target or n.is_ancestor_of(target):
			ctx.append_error("Cannot reparent '%s' into itself or its own descendant." % n.name)
			continue
		var old_parent = n.get_parent()
		a.do_method(n, &"reparent", [target, true])
		a.do_method(n, &"set_owner", [TreeUtil.owner_for(target)])
		a.undo_method(n, &"reparent", [old_parent, true])
		a.undo_method(old_parent, &"move_child", [n, n.get_index()])
		a.undo_method(n, &"set_owner", [n.owner])
		moved.append(n)
	a.commit()

	for n in moved:
		ctx.append_output(TreeUtil.path_of(n))
	return ExitCode.OK if not moved.is_empty() else ExitCode.FAIL

