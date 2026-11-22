extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const TreeUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/tree_util.gd")

const _HELP = \
"Attach a script to the stdin nodes.
Usage: ... | tree attach <res://script.gd>"


static func get_command_name() -> String:
	return "attach"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": 1,
	})


func _execute(ctx:Context):
	var script_path = positional_args[0]
	# ResourceLoader follows export remaps; the .gd file itself is absent in exported packs.
	if not ResourceLoader.exists(script_path):
		ctx.append_error("Script does not exist: " + script_path)
		return ExitCode.FAIL
	var script = load(script_path)
	if not script is Script:
		ctx.append_error("Not a script: " + script_path)
		return ExitCode.FAIL

	var nodes = TreeUtil.resolve_targets(ctx)
	if nodes.is_empty():
		return ExitCode.FAIL

	var a = TreeUtil.action(ctx, "Attach %s to %s node(s)" % [script_path.get_file(), nodes.size()])
	for n:Node in nodes:
		a.do_method(n, &"set_script", [script])
		a.undo_method(n, &"set_script", [n.get_script()])
	a.commit()
	ctx.append_output("Attached %s to %s node(s)." % [script_path.get_file(), nodes.size()])
	return ExitCode.OK

