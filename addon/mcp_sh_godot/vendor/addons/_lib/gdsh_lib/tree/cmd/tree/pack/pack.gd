extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const TreeUtil = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/tree/src/tree_util.gd")

const _HELP = \
"Save the first stdin node's subtree as a PackedScene file and print the file path (pipe into 'open').
The live tree is not changed.
Usage: ... | tree pack <res://dest.tscn>"


static func get_command_name() -> String:
	return "pack"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": 1,
	})


func _execute(ctx:Context):
	var targets = TreeUtil.resolve_targets(ctx)
	if targets.is_empty():
		return ExitCode.FAIL

	var dest = positional_args[0]
	if dest.get_extension() == "":
		dest += ".tscn"

	# Pack a copy: nodes must be owned by the packed root to be saved, and re-owning the
	# live nodes would detach them from their scene. Owners inside the copy (nested scene
	# internals) are kept.
	var copy:Node = targets[0].duplicate()
	if not is_instance_valid(copy):
		ctx.append_error("Could not duplicate: " + TreeUtil.path_of(targets[0]))
		return ExitCode.FAIL
	for n:Node in TreeUtil.walk(copy):
		if n == copy:
			continue
		var owner_node = n.owner
		if not is_instance_valid(owner_node) or not (owner_node == copy or copy.is_ancestor_of(owner_node)):
			n.owner = copy

	var packed = PackedScene.new()
	var err = packed.pack(copy)
	copy.free()
	if err != OK:
		ctx.append_error("Pack failed (error %s): %s" % [err, error_string(err)])
		return ExitCode.FAIL

	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	err = ResourceSaver.save(packed, dest)
	if err != OK:
		ctx.append_error("Save failed (error %s): %s" % [err, error_string(err)])
		return ExitCode.FAIL

	Utils.filesystem_changed(ctx)
	ctx.append_output(dest)
	return ExitCode.OK

