extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const TreeUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/tree_util.gd")

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
	
	var inputs = ctx.stdin.split("\n", false)
	if inputs.is_empty():
		ctx.append_error("Must pass nodes via stdin.")
		return ExitCode.FAIL
	
	for np in inputs:
		np = np.trim_suffix("\n")
		if np == "/root":
			ctx.append_output("Cannot get root's parent.")
			continue
		
		ctx.append_output(np.get_base_dir())
	
	return ExitCode.OK

