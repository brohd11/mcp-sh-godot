extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Search file contents across the project.
Outputs one 'res://path:line:text' per match (pipeable).
Usage: editor search <pattern> [--ext=gd] [--regex] [--ignore-case]"

const _TEXT_EXTS = ["gd", "tscn", "tres", "cfg", "txt", "md", "json", "csv", "gdshader", "import", "gdsh"]

var ext_flag := ""
var regex_flag := false
var ignore_case_flag := false

static func get_command_name() -> String:
	return "search"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": 1,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--ext=", {&"help": "Restrict to files with this extension.", &"trailing_char": ""})
	options.add_option("--regex", {&"help": "Treat the pattern as a regular expression."})
	options.add_option("--ignore-case", {&"help": "Case-insensitive match."})
	return options.get_options()

func _process_flag(flag:String):
	if flag.begins_with("--ext="):
		ext_flag = _get_flag_value(flag).lstrip(".")
	elif flag == "--regex":
		regex_flag = true
	elif flag == "--ignore-case":
		ignore_case_flag = true

func _execute(ctx:Context):
	var pattern = positional_args[0]
	var regex:RegEx
	if regex_flag:
		regex = RegEx.new()
		if regex.compile(("(?i)" if ignore_case_flag else "") + pattern) != OK:
			ctx.append_error("Invalid regex: " + pattern)
			return ExitCode.FAIL

	var hits := 0
	for path in Utils.file_paths(ctx):
		var ext = path.get_extension()
		if ext_flag != "":
			if ext != ext_flag:
				continue
		elif not ext in _TEXT_EXTS:
			continue

		var text = FileAccess.get_file_as_string(path)
		if text == "":
			continue
		var line_no := 0
		for line in text.split("\n"):
			line_no += 1
			var matched:bool
			if regex_flag:
				matched = regex.search(line) != null
			elif ignore_case_flag:
				matched = line.containsn(pattern)
			else:
				matched = line.contains(pattern)
			if matched:
				ctx.append_output("%s:%s:%s" % [path, line_no, line.strip_edges()])
				hits += 1

	if hits == 0:
		ctx.append_error("No matches for: " + pattern)
		return ExitCode.FAIL

