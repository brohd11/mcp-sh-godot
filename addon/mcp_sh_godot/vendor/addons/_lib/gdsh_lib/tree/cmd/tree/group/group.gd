extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const TreeUtil = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/tree/src/tree_util.gd")

const _HELP = \
"Manage groups on the stdin nodes.
Usage:
  ... | tree group add <name>      add nodes to a group (persistent)
  ... | tree group remove <name>   remove nodes from a group
  ... | tree group list            list each node's groups"


static func get_command_name() -> String:
	return "group"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:1,max:2",
	})


func _execute(ctx:Context):
	var action = positional_args[0]
	if not action in ["add", "remove", "list"]:
		ctx.append_error("Unknown action '%s' (expected add|remove|list)." % action)
		return ExitCode.FAIL
	if action != "list" and positional_args.size() < 2:
		ctx.append_error("'%s' requires a group name." % action)
		return ExitCode.FAIL

	var nodes = TreeUtil.resolve_targets(ctx)
	if nodes.is_empty():
		return ExitCode.FAIL

	var group_name = positional_args[1] if positional_args.size() > 1 else ""
	var a = TreeUtil.action(ctx, "%s group [%s]" % [action.capitalize(), group_name]) if action != "list" else null
	for n:Node in nodes:
		var node_path = TreeUtil.path_of(n)
		match action:
			"add":
				if not n.is_in_group(group_name):
					a.do_method(n, &"add_to_group", [group_name, true])
					a.undo_method(n, &"remove_from_group", [group_name])
				ctx.append_output("%s + [%s]" % [node_path, group_name])
			"remove":
				if n.is_in_group(group_name):
					a.do_method(n, &"remove_from_group", [group_name])
					a.undo_method(n, &"add_to_group", [group_name, true])
				ctx.append_output("%s - [%s]" % [node_path, group_name])
			"list":
				var groups := []
				for g in n.get_groups():
					if not str(g).begins_with("_"):
						groups.append(str(g))
				ctx.append_output("%s: %s" % [node_path, ", ".join(groups)])

	if a != null:
		a.commit()
	return ExitCode.OK

