extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const TreeUtil = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/tree/src/tree_util.gd")

const _HELP = \
"Get the node's parent's path.
Usage:
... | tree parent"

static func get_command_name() -> String:
	return "parent"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP
		})

func _execute(ctx:Context) -> int:
	var nodes = TreeUtil.resolve_targets(ctx)
	if nodes.is_empty():
		return ExitCode.FAIL
	var failed := false
	for n:Node in nodes:
		var parent = n.get_parent()
		if parent == null:
			ctx.append_error("Cannot get root's parent.")
			failed = true
			continue
		ctx.append_output(TreeUtil.path_of(parent))
	return ExitCode.FAIL if failed else ExitCode.OK

