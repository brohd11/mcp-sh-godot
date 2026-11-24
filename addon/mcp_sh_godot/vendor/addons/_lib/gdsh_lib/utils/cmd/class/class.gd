extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const _NAME_COLOR = Color.SKY_BLUE
const _PARENT_COLOR = Color("4d819a")

const _HELP = \
"Introspect an engine class or a user global class (API reference).
Resolves <name> via ClassDB, falling back to a registered global class name.
With no section flag, prints a compact summary (parent + counts + lists).
Usage: class <ClassName> [--methods] [--props] [--signals] [--constants] [--inherits] [--inheritors]"

var methods_flag := false
var props_flag := false
var signals_flag := false
var constants_flag := false
var inherits_flag := false
var inheritors_flag := false

static func get_command_name() -> String:
	return "class"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": "min:1,max:1",
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--methods", {&"help": "List the class's own methods."})
	options.add_option("--props", {&"help": "List the class's own properties."})
	options.add_option("--signals", {&"help": "List the class's own signals."})
	options.add_option("--constants", {&"help": "List the class's own integer constants."})
	options.add_option("--inherits", {&"help": "Print the parent inheritance chain."})
	options.add_option("--inheritors", {&"help": "List classes that inherit from this one."})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--methods":
		methods_flag = true
	elif flag == "--props":
		props_flag = true
	elif flag == "--signals":
		signals_flag = true
	elif flag == "--constants":
		constants_flag = true
	elif flag == "--inherits":
		inherits_flag = true
	elif flag == "--inheritors":
		inheritors_flag = true

func _execute(ctx:Context):
	var name = positional_args[0]

	# Engine class -> ClassDB. Otherwise try a registered global class script.
	if ClassDB.class_exists(name):
		return _report_engine_class(ctx, name)

	var script_path = Utils.get_all_global_class_paths().get(name, "")
	# ResourceLoader follows export remaps; the .gd file itself is absent in exported packs.
	if script_path != "" and ResourceLoader.exists(script_path):
		return _report_script_class(ctx, name, script_path)

	ctx.append_error("Unknown class (not in ClassDB, not a registered global class): " + name)
	return ExitCode.FAIL

func _any_section_flag() -> bool:
	return methods_flag or props_flag or signals_flag or constants_flag or inherits_flag or inheritors_flag

func _report_engine_class(ctx:Context, name:String):
	var summary := not _any_section_flag()

	if summary:
		var header = Utils.color_text(name, _NAME_COLOR)
		var parent = ClassDB.get_parent_class(name)
		if parent != "":
			header += " : " + Utils.color_text(parent, _PARENT_COLOR)
		ctx.append_output(header)

	if inherits_flag:
		var chain = []
		var cur = ClassDB.get_parent_class(name)
		while cur != "":
			chain.append(cur)
			cur = ClassDB.get_parent_class(cur)
		ctx.append_output(_section("inherits", summary))
		for c in chain:
			ctx.append_output("  " + c)

	var methods = ClassDB.class_get_method_list(name, true)
	if methods_flag or summary:
		ctx.append_output(_section("methods (%s)" % methods.size(), summary))
		for m in methods:
			ctx.append_output("  " + _format_method(m))

	var props = _filter_props(ClassDB.class_get_property_list(name, true))
	if props_flag or summary:
		ctx.append_output(_section("properties (%s)" % props.size(), summary))
		for p in props:
			ctx.append_output("  " + _format_property(p))

	var sigs = ClassDB.class_get_signal_list(name, true)
	if signals_flag or summary:
		ctx.append_output(_section("signals (%s)" % sigs.size(), summary))
		for s in sigs:
			ctx.append_output("  " + _format_method(s))

	if constants_flag:
		var consts = ClassDB.class_get_integer_constant_list(name, true)
		ctx.append_output(_section("constants (%s)" % consts.size(), summary))
		for c in consts:
			ctx.append_output("  " + c + " = " + str(ClassDB.class_get_integer_constant(name, c)))

	if inheritors_flag:
		var subs = ClassDB.get_inheriters_from_class(name)
		ctx.append_output(_section("inheritors (%s)" % subs.size(), summary))
		for s in subs:
			ctx.append_output("  " + s)

	return ExitCode.OK

func _report_script_class(ctx:Context, name:String, script_path:String):
	var script:Script = load(script_path)
	if not is_instance_valid(script):
		ctx.append_error("Could not load global class script: " + script_path)
		return ExitCode.FAIL

	var summary := not _any_section_flag()
	if summary:
		var header = Utils.color_text(name, _NAME_COLOR) + " : " + Utils.color_text(script.get_instance_base_type(), _PARENT_COLOR)
		ctx.append_output(header + "  " + script_path)

	var methods = script.get_script_method_list()
	if methods_flag or summary:
		ctx.append_output(_section("methods (%s)" % methods.size(), summary))
		for m in methods:
			ctx.append_output("  " + _format_method(m))

	var props = _filter_props(script.get_script_property_list())
	if props_flag or summary:
		ctx.append_output(_section("properties (%s)" % props.size(), summary))
		for p in props:
			ctx.append_output("  " + _format_property(p))

	var sigs = script.get_script_signal_list()
	if signals_flag or summary:
		ctx.append_output(_section("signals (%s)" % sigs.size(), summary))
		for s in sigs:
			ctx.append_output("  " + _format_method(s))

	if inherits_flag:
		ctx.append_output(_section("inherits", summary))
		ctx.append_output("  " + script.get_instance_base_type())

	return ExitCode.OK

func _section(title:String, summary:bool) -> String:
	# In summary mode sections are headers; with explicit flags keep them too for clarity.
	return Utils.color_text(title + ":", _NAME_COLOR)

func _format_method(m:Dictionary) -> String:
	var arg_strs = []
	for a in m.get("args", []):
		arg_strs.append(_type_name(a) + " " + a.get("name", ""))
	var line = m.get("name", "") + "(" + ", ".join(arg_strs) + ")"
	var ret = m.get("return", {})
	if ret is Dictionary:
		var rt = _return_name(ret)
		if rt != "" and rt != "void":
			line += " -> " + rt
	return line

func _format_property(p:Dictionary) -> String:
	return _type_name(p) + " " + p.get("name", "")

func _filter_props(props:Array) -> Array:
	# Drop category/group/subgroup header entries (same filter as 'inspect').
	var out := []
	for p in props:
		var usage:int = p.get("usage", 0)
		if usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
			continue
		out.append(p)
	return out

func _return_name(info:Dictionary) -> String:
	# A nil return type is 'void' unless the method is explicitly Variant-returning.
	var t:int = info.get("type", TYPE_NIL)
	if t == TYPE_NIL and not (int(info.get("usage", 0)) & PROPERTY_USAGE_NIL_IS_VARIANT):
		return "void"
	return _type_name(info)

func _type_name(info:Dictionary) -> String:
	var cls = info.get("class_name", "")
	if cls != "":
		return str(cls)
	var t:int = info.get("type", TYPE_NIL)
	if t == TYPE_NIL:
		return "Variant"
	return type_string(t)

