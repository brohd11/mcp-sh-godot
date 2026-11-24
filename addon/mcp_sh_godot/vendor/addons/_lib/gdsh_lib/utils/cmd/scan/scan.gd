extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Search scripts for a pattern, reporting only UNCOMMENTED matches (code that will run).
Scripts come from positional paths and/or stdin (one path per line); with no paths it
scans every project file of the target extension. Outputs 'res://path:line:text' (pipeable).
Note: a '#' inside a string literal before the match may be misread as a comment.
Usage: scan <pattern> [res://path ...] [--regex] [--ignore-case]
       scan --prints [res://path ...] [--include-commented]"

# print, prints, printerr, printraw, print_debug, print_rich, print_verbose
const _PRINTS_PATTERN = r"(?<![\w.])(print|prints|printerr|printraw|print_debug|print_rich|print_verbose)\s*\("

var prints_flag := false
var include_commented_flag := false
var regex_flag := false
var ignore_case_flag := false
var ext_flag := "gd"

static func get_command_name() -> String:
	return "scan"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": "min:0",
		&"allow_positional_paths": true,
	})

func _get_completions(completion:Completion) -> Dictionary:
	# The first positional is a pattern unless the print preset supplies it.
	if not prints_flag and positional_arg_index == 0:
		return get_flags(true)
	return _get_completion_std_w_context(completion)

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--prints", {&"short": "p", &"help": "Use the print-family preset instead of a pattern (print, prints, printerr, print_debug, ...)."})
	options.add_option("--include-commented", {&"short": "c", &"help": "Also report matches on commented lines."})
	options.add_option("--regex", {&"short": "E", &"help": "Treat the pattern as a regular expression."})
	options.add_option("--ignore-case", {&"short": "i", &"help": "Case-insensitive match."})
	options.add_option("--ext=", {&"help": "Extension to scan when no paths are given (default: gd).", &"trailing_char": ""})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--prints":
		prints_flag = true
	elif flag == "--include-commented":
		include_commented_flag = true
	elif flag == "--regex":
		regex_flag = true
	elif flag == "--ignore-case":
		ignore_case_flag = true
	elif flag.begins_with("--ext="):
		ext_flag = _get_flag_value(flag).lstrip(".")

func _execute(ctx:Context):
	# Resolve pattern and paths from positionals. Without --prints the first
	# positional is the pattern and the rest are paths; with --prints every
	# positional is a path.
	var pattern := ""
	var paths:Array[String] = []
	if prints_flag:
		pattern = _PRINTS_PATTERN
		paths.append_array(positional_args)
	else:
		if positional_args.is_empty():
			ctx.append_error("No pattern given (use --prints for the print preset).")
			return ExitCode.FAIL
		pattern = positional_args[0]
		for i in range(1, positional_args.size()):
			paths.append(complete_path(positional_args[i]))

	# Paths may also arrive via stdin (one per line), e.g. from `find`.
	for line in ctx.stdin.split("\n", false):
		var stripped = line.strip_edges()
		if stripped != "":
			paths.append(complete_path(stripped))

	# Compile the matcher. --prints is always regex; otherwise honour --regex.
	var use_regex = regex_flag or prints_flag
	var regex:RegEx
	if use_regex:
		regex = RegEx.new()
		if regex.compile(("(?i)" if ignore_case_flag else "") + pattern) != OK:
			ctx.append_error("Invalid regex: " + pattern)
			return ExitCode.FAIL

	# No explicit paths -> scan cwd (target extension only).
	var local_cwd = ProjectSettings.localize_path(ctx.cwd)
	if paths.is_empty():
		for path in Utils.file_paths(ctx):
			if path.get_extension() == ext_flag and path.begins_with(local_cwd):
				paths.append(path)

	var hits := 0
	for path in paths:
		var text = FileAccess.get_file_as_string(path)
		if text == "":
			continue
		var line_no := 0
		for line in text.split("\n"):
			line_no += 1
			var match_idx := _match_index(line, pattern, regex, use_regex)
			if match_idx < 0:
				continue
			if not include_commented_flag and _is_commented(line, match_idx):
				continue
			ctx.append_output("%s:%s:%s" % [path, line_no, line.strip_edges()])
			hits += 1

	if hits == 0:
		ctx.append_error("No matches for: " + ("--prints" if prints_flag else pattern))
		return ExitCode.FAIL
	return ExitCode.OK

# Returns the start index of the match within `line`, or -1 if none.
func _match_index(line:String, pattern:String, regex:RegEx, use_regex:bool) -> int:
	if use_regex:
		var m := regex.search(line)
		return m.get_start() if is_instance_valid(m) else -1
	if ignore_case_flag:
		return line.findn(pattern)
	return line.find(pattern)

# A match is "commented" if the line is a comment line, or a '#' appears before it.
func _is_commented(line:String, match_idx:int) -> bool:
	if line.strip_edges().begins_with("#"):
		return true
	var hash_idx := line.find("#")
	return hash_idx != -1 and hash_idx < match_idx

