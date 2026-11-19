extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const TreeUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/tree_util.gd")

const _NAME_COLOR = Color.SKY_BLUE
const _PROP_COLOR = Color("4d819a")

const _HELP = \
"List the properties of the stdin nodes, or of a resource given by path.
Usage:
  ... | tree inspect [--methods]
  tree inspect <res://resource.tres> [--methods]"

var methods_flag := false


static func get_command_name() -> String:
	return "inspect"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:0,max:1",
	})


func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--methods", {&"short": "m", &"help": "Also list the object's methods."})
	return options.get_options()


func _process_flag(flag:String):
	if flag == "--methods":
		methods_flag = true


func _execute(ctx:Context):
	var targets := []
	if not positional_args.is_empty():
		var path = positional_args[0]
		if not (path.begins_with("res://") or path.begins_with("user://")):
			ctx.append_error("Expected a res:// or user:// resource path (pipe node paths instead): " + path)
			return ExitCode.FAIL
		if not ResourceLoader.exists(path):
			ctx.append_error("Resource does not exist: " + path)
			return ExitCode.FAIL
		targets.append(load(path))
	else:
		targets = TreeUtil.resolve_targets(ctx)
		if targets.is_empty():
			return ExitCode.FAIL

	for obj in targets:
		# A checkpoint can yield a frame; skip nodes freed meanwhile.
		if await ctx.checkpoint():
			return ExitCode.CANCELLED
		if is_instance_valid(obj):
			_print_object(ctx, obj)
	return ExitCode.OK


func _print_object(ctx:Context, obj:Object):
	ctx.append_output(Utils.color_text(obj.get_class(), _NAME_COLOR))
	for p in obj.get_property_list():
		var usage:int = p.get("usage", 0)
		if usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
			continue
		if not (usage & PROPERTY_USAGE_EDITOR) and not (usage & PROPERTY_USAGE_STORAGE):
			continue
		var name = p.get("name", "")
		if name == "":
			continue
		ctx.append_output("  " + Utils.color_text(name, _PROP_COLOR) + " = " + str(obj.get(name)))

	if methods_flag:
		ctx.append_output(Utils.color_text("methods:", _NAME_COLOR))
		for m in obj.get_method_list():
			ctx.append_output("  " + m.get("name", ""))

