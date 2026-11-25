extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/data/src/config_command.gd"

const _HELP = \
"Write to a ConfigFile, creating it if missing: one key, or a section from stdin key=value lines
(merged in; `get FILE SECTION` prints that form). A value is a Godot literal (12, true,
Vector2(1, 2), \"12\"), else stored as a String; null erases the key, as ConfigFile does.
--erase removes the key, or the section without one. Saving drops the file's comments.
Usage: data config_file set [--erase] [--no-scan] <file> <section> [<key> [value]]"

var erase_flag := false
var no_scan_flag := false

static func get_command_name():
	return "set"

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:2,max:4",
		&"allow_positional_paths": true,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--erase", {
		&"help": "Remove the key, or the whole section when no key is given.",
	})
	options.add_option("--no-scan", {
		&"help": "Don't rescan the editor FileSystem after creating the file.",
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--erase":
		erase_flag = true
	elif flag == "--no-scan":
		no_scan_flag = true

func _execute(ctx:Context):
	var path = complete_path(positional_args[0])
	var section = positional_args[1]
	var key = positional_args[2] if positional_args.size() > 2 else ""
	if erase_flag and positional_args.size() == 4:
		ctx.append_error("--erase takes no value.")
		return ExitCode.ERR
	if not erase_flag and positional_args.size() == 3:
		ctx.append_error("Need a value for %s (or pass --erase)." % key)
		return ExitCode.ERR

	var created = not FileAccess.file_exists(path)
	var cfg = ConfigFile.new()
	if created and erase_flag:
		ctx.append_error("File doesn't exist: " + path)
		return ExitCode.FAIL
	if not created:
		var loaded = _load_cfg(path)
		if loaded.has("error"):
			ctx.append_error(loaded.error)
			return ExitCode.FAIL
		cfg = loaded.cfg

	var done := ""
	if erase_flag:
		if not cfg.has_section(section) or (not key.is_empty() and not cfg.has_section_key(section, key)):
			ctx.append_error("Nothing to erase: [%s] %s in %s" % [section, key, path])
			return ExitCode.FAIL
		if key.is_empty():
			cfg.erase_section(section)
		else:
			cfg.erase_section_key(section, key)
		done = "Erased [%s] %s" % [section, key]
	elif not key.is_empty():
		cfg.set_value(section, key, ConfigData.parse_value(positional_args[3]))
		done = "Set [%s] %s" % [section, key]
	else:
		var parsed = ConfigData.parse_lines(ctx.stdin)
		if parsed.has("error"):
			ctx.append_error(parsed.error)
			return ExitCode.ERR
		if parsed.values.is_empty():
			ctx.append_error("Need <key> <value>, or key=value lines on stdin.")
			return ExitCode.ERR
		for name in parsed.values:
			cfg.set_value(section, name, parsed.values[name])
		done = "Set %d keys in [%s]" % [parsed.values.size(), section]

	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err = cfg.save(path)
	if err != OK:
		ctx.append_error("Can't write %s: %s" % [path, error_string(err)])
		return ExitCode.FAIL
	ctx.append_output("%s in %s" % [done.strip_edges(), path])
	if created and not no_scan_flag and Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	return ExitCode.OK

