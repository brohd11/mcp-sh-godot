extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const TreeUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/tree_util.gd")

const _HELP = \
"Rename the one stdin node and print its new absolute path.
Usage: ... | tree rename <new_name>"


static func get_command_name() -> String:
	return "rename"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": 1,
	})


func _execute(ctx:Context):
	var nodes = TreeUtil.resolve_targets(ctx)
	if nodes.size() != 1:
		ctx.append_error("rename expects exactly one target node, got %s." % nodes.size())
		return ExitCode.FAIL

	var node:Node = nodes[0]
	var a = TreeUtil.action(ctx, "Rename node: %s" % node.name)
	a.do_property(node, &"name", positional_args[0])
	a.undo_property(node, &"name", node.name)
	a.commit()

	ctx.append_output(TreeUtil.path_of(node))
	return ExitCode.OK

