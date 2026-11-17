extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const TreeUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/tree_util.gd")

const _HELP = \
"Get or set a property on the stdin nodes, printing each node's value one per line.
Usage:
  ... | tree prop <name>              print the property for each node
  ... | tree prop <name> <value>      set the property on each node
Value is converted to the property's current type. Nested paths work, e.g. 'position:x'.
--verbose prints 'path.name = value' instead of the bare value."

var verbose_flag := false


static func get_command_name() -> String:
	return "prop"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:1,max:2",
	})


func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--verbose", {&"short": "v", &"help": "Print 'path.name = value' instead of the bare value."})
	return options.get_options()


func _process_flag(flag:String):
	if flag == "--verbose":
		verbose_flag = true


func _execute(ctx:Context):
	var nodes = TreeUtil.resolve_targets(ctx)
	if nodes.is_empty():
		return ExitCode.FAIL

	var prop_name = positional_args[0]
	var prop_path := NodePath(prop_name)

	if positional_args.size() > 1:
		var a = TreeUtil.action(ctx, "Set %s on %s node(s)" % [prop_name, nodes.size()])
		for n:Node in nodes:
			var current = n.get_indexed(prop_path)
			var converted = Utils_Value.convert(positional_args[1], typeof(current), n.get_class())
			a.do_method(n, &"set_indexed", [prop_path, converted])
			a.undo_method(n, &"set_indexed", [prop_path, current])
		a.commit()

	for n:Node in nodes:
		var value = str(n.get_indexed(prop_path))
		if verbose_flag:
			ctx.append_output("%s.%s = %s" % [TreeUtil.path_of(n), prop_name, value])
		else:
			ctx.append_output(value)
	return ExitCode.OK

