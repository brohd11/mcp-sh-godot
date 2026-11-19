extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const TreeUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/tree_util.gd")

const _NAME_COLOR = Color.SKY_BLUE
const _CLASS_COLOR = Color("7b7f85")
const _SCRIPT_COLOR = Color("4d819a")

const _HELP = \
"List the children of each stdin node, or all descendants with --recursive, one absolute path per line.
Class filters match inheriting classes unless --exact.
Usage: ... | tree nodes [ClassName] [--include-self] [--recursive] [--exact] [--script=res://path.gd] [--owned] [--pretty]"

var type_flag := ""
var include_self_flag := false
var recursive_flag := false
var exact_flag := false
var script_flag := ""
var owned_flag := false
var pretty_flag := false


static func get_command_name() -> String:
	return "nodes"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:0,max:1",
	})


func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--include-self", {&"short": "i", &"help": "Also list each stdin node itself, before its children."})
	options.add_option("--recursive", {&"short": "r", &"help": "List all descendants, not just direct children."})
	options.add_option("--type=", {
		&"help": "Only nodes of this class (same as the positional ClassName).",
		&"trailing_char": "",
		&"flag_completion": {"type": FlagType.CLASS},
	})
	options.add_option("--exact", {&"short": "e", &"help": "Match the class exactly, not inheriting classes."})
	options.add_option("--script=", {
		&"help": "Only nodes using this script (res:// path or global class name).",
		&"trailing_char": "",
		&"flag_completion": {"type": FlagType.FILE, "ext": ["gd"]},
	})
	options.add_option("--owned", {&"short": "o", &"help": "Only nodes in the input's scene (hides nested scene internals)."})
	options.add_option("--pretty", {&"short": "p", &"help": "Indented, colored tree (display only)."})
	return options.get_options()


func _process_flag(flag:String):
	if flag == "--include-self":
		include_self_flag = true
	elif flag == "--recursive":
		recursive_flag = true
	elif flag.begins_with("--type="):
		type_flag = _get_flag_value(flag)
	elif flag == "--exact":
		exact_flag = true
	elif flag.begins_with("--script="):
		script_flag = Utils.unquote(_get_flag_value(flag))
	elif flag == "--owned":
		owned_flag = true
	elif flag == "--pretty":
		pretty_flag = true


func _execute(ctx:Context):
	if not positional_args.is_empty():
		type_flag = positional_args[0]
	if type_flag != "" and not ClassDB.class_exists(type_flag):
		ctx.append_error("Unknown class: " + type_flag)
		return ExitCode.FAIL
	if script_flag != "" and not script_flag.is_absolute_path():
		script_flag = Utils.get_all_global_class_paths().get(script_flag, script_flag)

	var inputs = TreeUtil.resolve_targets(ctx)
	if inputs.is_empty():
		return ExitCode.FAIL

	for input in inputs:
		if not is_instance_valid(input):
			continue
		# New children of input would get this owner; --owned keeps nodes in that same scene.
		var scene_owner = TreeUtil.owner_for(input) if owned_flag else null
		if pretty_flag:
			if include_self_flag:
				_print_pretty(ctx, input, 0, scene_owner, true)
			else:
				for child in input.get_children():
					_print_pretty(ctx, child, 0, scene_owner)
			continue
		var nodes = TreeUtil.walk(input).slice(1) if recursive_flag else input.get_children()
		if include_self_flag:
			nodes.push_front(input)
		for n in nodes:
			# A checkpoint can yield a frame; skip nodes freed meanwhile.
			if await ctx.checkpoint():
				return ExitCode.CANCELLED
			if is_instance_valid(n) and _passes(n, scene_owner):
				ctx.append_output(TreeUtil.path_of(n))
	return ExitCode.OK


func _passes(n:Node, scene_owner:Node) -> bool:
	if type_flag != "":
		var cls = n.get_class()
		if exact_flag and cls != type_flag:
			return false
		if not exact_flag and not ClassDB.is_parent_class(cls, type_flag):
			return false
	if script_flag != "":
		var script = n.get_script()
		if not is_instance_valid(script) or script.resource_path != script_flag:
			return false
	# The scene root itself has no owner; only an --include-self input can be it.
	if scene_owner != null and n.owner != scene_owner and n != scene_owner:
		return false
	return true


## with_children lists node's children even without --recursive (an --include-self input).
func _print_pretty(ctx:Context, node:Node, depth:int, scene_owner:Node, with_children:=false):
	if ctx.is_cancelled():
		return
	if _passes(node, scene_owner):
		var line = "  ".repeat(depth) + Utils.color_text(node.name, _NAME_COLOR)
		line += "  " + Utils.color_text(node.get_class(), _CLASS_COLOR)
		var script = node.get_script()
		if is_instance_valid(script):
			line += "  " + Utils.color_text(script.resource_path.get_file(), _SCRIPT_COLOR)
		ctx.append_output(line)
	if recursive_flag or with_children:
		for child in node.get_children():
			_print_pretty(ctx, child, depth + 1, scene_owner)

