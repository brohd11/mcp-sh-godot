extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/data/src/config_command.gd"

const _HELP = \
"Print a ConfigFile as Godot parses it: the whole file, a section's key=value lines, or one value
(a String prints bare). --json prints JSON instead; Godot types such as Vector2 become strings.
Usage: data config_file get [--json] <file> [section] [key]"

var json_flag := false

static func get_command_name():
	return "get"

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:1,max:3",
		&"allow_positional_paths": true,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--json", {
		&"help": "Print JSON: {section: {key: value}}, {key: value}, or the value.",
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--json":
		json_flag = true

func _execute(ctx:Context):
	var path = complete_path(positional_args[0])
	var loaded = _load_cfg(path)
	if loaded.has("error"):
		ctx.append_error(loaded.error)
		return ExitCode.FAIL
	var cfg:ConfigFile = loaded.cfg
	var section = positional_args[1] if positional_args.size() > 1 else ""
	if not section.is_empty() and not cfg.has_section(section):
		ctx.append_error("No section [%s] in %s" % [section, path])
		return ExitCode.FAIL
	if positional_args.size() == 3:
		var key = positional_args[2]
		if not cfg.has_section_key(section, key):
			ctx.append_error("No key %s in [%s] of %s" % [key, section, path])
			return ExitCode.FAIL
		var value = cfg.get_value(section, key)
		if json_flag:
			ctx.append_output(JSON.stringify(value))
		else:
			ctx.append_output(value if value is String else var_to_str(value))
	elif json_flag:
		ctx.append_output(JSON.stringify(ConfigData.to_dict(cfg, section), "\t"))
	elif section.is_empty():
		ctx.append_output(ConfigData.file_text(cfg))
	else:
		ctx.append_output(ConfigData.section_text(cfg, section))
	return ExitCode.OK

