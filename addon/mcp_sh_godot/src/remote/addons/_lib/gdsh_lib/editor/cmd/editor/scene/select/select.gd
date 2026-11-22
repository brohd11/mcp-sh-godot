extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const NodePaths = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/node_paths.gd")


const _HELP = \
"Print the selected node paths, or select/deselect the node paths from stdin.
Paths are absolute, so the output pipes into 'tree' commands.
Usage:
  editor scene select                    print the selected node paths
  ... | editor scene select              select the piped nodes (replacing the selection)
  ... | editor scene select --add        add the piped nodes to the selection
  editor scene select --deselect         clear the selection
  ... | editor scene select --deselect   deselect the piped nodes"

var add_flag:=false
var deselect_flag:=false

static func get_command_name():
	return "select"

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--add", {
		&"help": "Add the piped nodes to the selection instead of replacing it."
	})
	options.add_option("--deselect", {
		&"help": "Deselect the piped nodes, or everything without stdin."
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--add":
		add_flag = true
	elif flag == "--deselect":
		deselect_flag = true

func _execute(ctx:Context):
	var edited_root = EditorInterface.get_edited_scene_root()
	if not is_instance_valid(edited_root):
		ctx.append_error("No edited scene open.")
		return ExitCode.FAIL

	var editor_selection = EditorInterface.get_selection()
	if ctx.stdin.strip_edges() == "":
		if deselect_flag:
			editor_selection.clear()
		else:
			for node in editor_selection.get_selected_nodes():
				ctx.append_output(NodePaths.path_of(node))
		return ExitCode.OK

	if not add_flag and not deselect_flag:
		editor_selection.clear()

	var failed := false
	for line in ctx.stdin.split("\n", false):
		var p = line.strip_edges()
		if p == "":
			continue
		if not NodePath(p).is_absolute():
			ctx.append_error("Not an absolute node path: " + p)
			failed = true
			continue
		var node = NodePaths.resolve(p)
		if not is_instance_valid(node):
			ctx.append_error("Node not found: " + p)
			failed = true
		elif node != edited_root and not edited_root.is_ancestor_of(node):
			ctx.append_error("Not in the edited scene: " + p)
			failed = true
		elif deselect_flag:
			editor_selection.remove_node(node)
		else:
			editor_selection.add_node(node)
	return ExitCode.FAIL if failed else ExitCode.OK

