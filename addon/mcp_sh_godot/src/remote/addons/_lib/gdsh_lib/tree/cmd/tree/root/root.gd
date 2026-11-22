extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const TreeUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/tree_util.gd")

const _HELP = \
"Print the SceneTree root path (/root), to start a tree command chain.
In the editor /root holds the editor's own UI (thousands of nodes); start from /scene or
'editor scene root' to work on the edited scene.
Usage: tree root | tree nodes"


static func get_command_name() -> String:
	return "root"


static func get_self_command_data() -> Dictionary:
	return _command_data({&"help": _HELP})


func _execute(ctx:Context):
	var root = TreeUtil.get_tree_root()
	if root == null:
		ctx.append_error("No SceneTree.")
		return ExitCode.FAIL
	ctx.append_output(TreeUtil.path_of(root))
	return ExitCode.OK

