extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Get or set an editor setting (EditorSettings).
Usage: settings esetting <name> [value]
  (no value)   print the current value
  <value>      set it (converted to the setting's current type)"

static func get_command_name() -> String:
	return "esetting"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:1,max:2",
	})

func _get_completions(_ctx:Completion):
	if not Engine.is_editor_hint() or not _positional_arg_index_valid():
		return {}
	var settings = EditorInterface.get_editor_settings()
	var options = Options.new()
	for p in settings.get_property_list():
		var name = p.get("name", "")
		if settings.has_setting(name):
			options.add_option(name, {&"trailing_char": " "})
	return options.get_options()

func _execute(ctx:Context):
	# Headless (gdsh CLI) has no EditorSettings; the call would be a script error.
	if not Engine.is_editor_hint():
		ctx.append_error("esetting needs the editor.")
		return ExitCode.FAIL
	var settings = EditorInterface.get_editor_settings()
	var name = positional_args[0]
	if not settings.has_setting(name):
		ctx.append_error("No such editor setting: " + name)
		return ExitCode.FAIL

	if positional_args.size() == 1:
		ctx.append_output(str(settings.get_setting(name)))
		return ExitCode.OK
	var new_val = positional_args[1]
	var converted = null
	var current = settings.get_setting(name)
	if new_val == "null":
		ctx.append_output("null erases setting: %s -> null" % [current])
	else:
		converted = Utils_Value.convert(new_val, typeof(current))
		if converted == null:
			ctx.append_error("Could not convert: %s -> %s" % [new_val, typeof(current)])
			return ExitCode.ERR
	settings.set_setting(name, converted)
	ctx.append_output("%s = %s" % [name, str(converted)])
	return ExitCode.OK

