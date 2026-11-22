extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const TreeUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/tree_util.gd")

const _HELP = \
"Duplicate the stdin nodes next to themselves and print the new absolute paths.
Copies are named <Name>_<first free int>, replacing a trailing _<int> on the source name.
--name and --suffix set the name instead (<NewName><Suffix>), numbered only when taken.
Usage: ... | tree duplicate [--name=NewName] [--suffix=Suffix]"

const _NUMBER_SUFFIX = "_\\d+$"

var name_flag := ""
var suffix_flag := ""


static func get_command_name() -> String:
	return "duplicate"


static func get_self_command_data() -> Dictionary:
	return _command_data({&"help": _HELP})


func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--name=", {
		&"help": "Name the copies NewName instead of the source name.",
		&"trailing_char": "",
	})
	options.add_option("--suffix=", {
		&"help": "Append Suffix to the name: NodeNameSuffix.",
		&"trailing_char": "",
	})
	return options.get_options()


func _process_flag(flag:String):
	if flag.begins_with("--name="):
		name_flag = Utils.unquote(_get_flag_value(flag))
	elif flag.begins_with("--suffix="):
		suffix_flag = Utils.unquote(_get_flag_value(flag))


func _execute(ctx:Context):
	var custom = name_flag + suffix_flag
	if custom != custom.validate_node_name():
		ctx.append_error("Invalid characters in node name: " + custom)
		return ExitCode.FAIL

	var nodes = TreeUtil.resolve_targets(ctx)
	if nodes.is_empty():
		return ExitCode.FAIL

	var a = TreeUtil.action(ctx, "Duplicate %s node(s)" % nodes.size())
	# Parent -> names taken, including copies named earlier in this command (none are added
	# until commit).
	var taken := {}
	var added := []
	for source:Node in nodes:
		var parent = source.get_parent()
		if parent == null:
			ctx.append_error("Cannot duplicate a node with no parent: " + TreeUtil.path_of(source))
			continue
		var dup:Node = source.duplicate()
		if not is_instance_valid(dup):
			ctx.append_error("Could not duplicate: " + TreeUtil.path_of(source))
			continue
		dup.name = _free_name(source, parent, taken)
		var scene_owner = TreeUtil.owner_for(parent)
		a.do_method(source, &"add_sibling", [dup, true])
		# set_owner needs the owner to be an ancestor, so these run after add_sibling. Owners inside
		# the copy (nested scene internals, or an instanced copy's own nodes) are kept.
		for n:Node in TreeUtil.walk(dup):
			var o = n.owner
			var inside = n != dup and is_instance_valid(o) \
				and (dup.is_ancestor_of(o) or (o == dup and dup.scene_file_path != ""))
			if not inside:
				a.do_method(n, &"set_owner", [scene_owner])
		a.do_reference(dup)
		a.undo_method(parent, &"remove_child", [dup])
		added.append(dup)
	if added.is_empty():
		return ExitCode.FAIL
	a.commit()

	for dup in added:
		ctx.append_output(TreeUtil.path_of(dup))
	return ExitCode.OK


func _free_name(source:Node, parent:Node, taken:Dictionary) -> String:
	if not taken.has(parent):
		var names := {}
		for child in parent.get_children():
			names[String(child.name)] = true
		taken[parent] = names
	var names:Dictionary = taken[parent]

	var base:String
	if name_flag != "" or suffix_flag != "":
		base = (name_flag if name_flag != "" else String(source.name)) + suffix_flag
		if not names.has(base):
			names[base] = true
			return base
	else:
		base = RegEx.create_from_string(_NUMBER_SUFFIX).sub(String(source.name), "")

	var x := 1
	while names.has("%s_%d" % [base, x]):
		x += 1
	var new_name = "%s_%d" % [base, x]
	names[new_name] = true
	return new_name

