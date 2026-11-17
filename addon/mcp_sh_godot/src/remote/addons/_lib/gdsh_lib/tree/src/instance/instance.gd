extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const TreeUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/tree_util.gd")

const _HELP = \
"Instance a scene under each stdin node and print the new absolute paths.
Usage: ... | tree instance <res://scene.tscn>"


static func get_command_name() -> String:
	return "instance"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": 1,
	})


func _execute(ctx:Context):
	var scene_path = positional_args[0]
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		ctx.append_error("Scene does not exist: " + scene_path)
		return ExitCode.FAIL
	var packed = load(scene_path)
	if not packed is PackedScene:
		ctx.append_error("Not a PackedScene: " + scene_path)
		return ExitCode.FAIL

	var parents = TreeUtil.resolve_targets(ctx)
	if parents.is_empty():
		return ExitCode.FAIL

	var a = TreeUtil.action(ctx, "Instance %s" % scene_path.get_file())
	var added := []
	for parent:Node in parents:
		var node = packed.instantiate()
		if not is_instance_valid(node):
			ctx.append_error("Failed to instantiate: " + scene_path)
			return ExitCode.FAIL
		a.do_method(parent, &"add_child", [node, true])
		a.do_method(node, &"set_owner", [TreeUtil.owner_for(parent)])
		a.do_reference(node)
		a.undo_method(parent, &"remove_child", [node])
		added.append(node)
	a.commit()

	for node in added:
		ctx.append_output(TreeUtil.path_of(node))
	return ExitCode.OK

