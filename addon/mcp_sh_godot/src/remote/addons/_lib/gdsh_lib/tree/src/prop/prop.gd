extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const TreeUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/tree_util.gd")

const _HELP = \
"Get or set a property on the stdin nodes, printing each node's value one per line.
Usage:
  ... | tree prop <name>              print the property for each node
  ... | tree prop <name> <value>      set the property on each node
Value is converted to the property's type (its declared type when unset, e.g. theme overrides).
'null' clears the value; object properties take a res:// path. Nested paths work, e.g. 'position:x'.
Nothing changes unless the value converts for every node.
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
		# Convert for every node first, so a bad value changes nothing and registers no undo.
		var changes := []
		for n:Node in nodes:
			if ctx.is_cancelled():
				return ExitCode.CANCELLED
			var current = n.get_indexed(prop_path)
			var converted = _convert(ctx, n, prop_path, current, positional_args[1])
			if converted is _Invalid:
				return ExitCode.FAIL
			changes.append([n, current, converted])
		var a = TreeUtil.action(ctx, "Set %s on %s node(s)" % [prop_name, nodes.size()])
		for change in changes:
			a.do_method(change[0], &"set_indexed", [prop_path, change[2]])
			a.undo_method(change[0], &"set_indexed", [prop_path, change[1]])
		a.commit()

	for n in nodes:
		# A checkpoint can yield a frame; skip nodes freed meanwhile.
		if await ctx.checkpoint():
			return ExitCode.CANCELLED
		if not is_instance_valid(n):
			continue
		var value = str(n.get_indexed(prop_path))
		if verbose_flag:
			ctx.append_output("%s.%s = %s" % [TreeUtil.path_of(n), prop_name, value])
		else:
			ctx.append_output(value)
	return ExitCode.OK


class _Invalid:
	pass


## The value for one node, or an _Invalid after reporting why. An unset property (null) has no
## type to convert to, so use its declared type, or infer one when it isn't listed.
func _convert(ctx:Context, n:Node, prop_path:NodePath, current, raw:String):
	if raw == "null":
		return null
	var target_type := typeof(current)
	if target_type == TYPE_NIL:
		var declared := _declared_type(n, prop_path)
		if declared == -1:
			ctx.append_error("No property '%s' on %s" % [prop_path, TreeUtil.path_of(n)])
			return _Invalid.new()
		target_type = declared
	var value
	if target_type == TYPE_OBJECT:
		value = load(raw) if (raw.begins_with("res://") or raw.begins_with("uid://")) and ResourceLoader.exists(raw) else null
	elif target_type == TYPE_NIL:
		value = Utils_Value.infer_type(raw)
	else:
		value = Utils_Value.convert(raw, target_type, n.get_class())
	if value == null:
		ctx.append_error("Cannot convert '%s' to %s for %s on %s" % [raw, type_string(target_type), prop_path, TreeUtil.path_of(n)])
		return _Invalid.new()
	return value


## A top-level property's declared Variant type; -1 when the node doesn't list it. Nested
## paths under an unset value can't be typed, so they report NIL (inferred from the text).
static func _declared_type(n:Node, prop_path:NodePath) -> int:
	var names = prop_path.get_as_property_path()
	if names.get_subname_count() != 1:
		return TYPE_NIL
	var name = str(names.get_subname(0))
	for info in n.get_property_list():
		if info.name == name:
			return info.type
	return -1

