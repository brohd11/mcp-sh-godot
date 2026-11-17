extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Find files under the current directory by name (one path per line).
Pattern matches the file name; use * and ? for globbing, otherwise it's a substring match.
Results are limited to the current directory (see cwd); cd elsewhere to change scope.
Usage: find <pattern> [--ext=tscn]"

var ext_flag := ""

static func get_command_name() -> String:
	return "find"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": 1,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--ext=", {
		&"help": "Only match files with this extension.",
		&"trailing_char": "",
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag.begins_with("--ext="):
		ext_flag = _get_flag_value(flag).lstrip(".")

func _execute(ctx:Context):
	var pattern = positional_args[0]
	var is_glob = pattern.contains("*") or pattern.contains("?")

	var root := ProjectSettings.localize_path(ctx.cwd)
	if not root.ends_with("/"):
		root += "/"

	var matches := 0
	for f in Utils.file_paths(ctx):
		if not f.begins_with(root):
			continue
		if ext_flag != "" and f.get_extension() != ext_flag:
			continue
		var file_name = f.get_file()
		var hit := false
		if is_glob:
			hit = file_name.matchn(pattern)
		else:
			hit = file_name.containsn(pattern)
		if hit:
			ctx.append_output(f)
			matches += 1

	if matches == 0:
		ctx.append_error("No files matched: " + pattern)
		return ExitCode.FAIL

