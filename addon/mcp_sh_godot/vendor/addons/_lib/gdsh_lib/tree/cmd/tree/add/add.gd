extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const TreeUtil = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/tree/src/tree_util.gd")

const _HELP = \
"Add a new node under each stdin node and print the new absolute paths.
The new node joins the parent's scene (owned by the parent's scene root).
Usage: ... | tree add <ClassName> [name]"


static func get_command_name() -> String:
	return "add"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:1,max:2",
	})


func _execute(ctx:Context):
	var type = positional_args[0]
	if not ClassDB.class_exists(type) or not ClassDB.can_instantiate(type):
		ctx.append_error("Cannot instantiate class: " + type)
		return ExitCode.FAIL
	if not ClassDB.is_parent_class(type, "Node"):
		ctx.append_error("Class is not a Node: " + type)
		return ExitCode.FAIL

	var parents = TreeUtil.resolve_targets(ctx)
	if parents.is_empty():
		return ExitCode.FAIL

	var a = TreeUtil.action(ctx, "Add %s" % type)
	var added := []
	for parent:Node in parents:
		var node:Node = ClassDB.instantiate(type)
		if positional_args.size() > 1:
			node.name = positional_args[1]
		a.do_method(parent, &"add_child", [node, true])
		a.do_method(node, &"set_owner", [TreeUtil.owner_for(parent)])
		a.do_reference(node)
		a.undo_method(parent, &"remove_child", [node])
		added.append(node)
	a.commit()

	for node in added:
		ctx.append_output(TreeUtil.path_of(node))
	return ExitCode.OK

