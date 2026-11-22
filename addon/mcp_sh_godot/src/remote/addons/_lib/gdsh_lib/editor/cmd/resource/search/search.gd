extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"


const _HELP = \
"Find project files by name, or by file content with --content.
Usage: resource search <term> [--content] [--dir=res://path]"

const _READABLE_EXTS = ["gd", "gdshader", "tres", "tscn", "cs","md", "cfg", "ini", "txt"]

var content_flag:=false
var dir_flag:=""

static func get_command_name():
	return "search"

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
		&"positional_count": 1,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--content", {
		&"help": "Match against file contents instead of file names."
	})
	options.add_option("--dir=", {
		&"help": "Restrict the search to this directory.",
		&"trailing_char": "",
		&"flag_completion": {"type": FlagType.DIR}
	})
	
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--content":
		content_flag = true
	elif flag.begins_with("--dir="):
		dir_flag = _get_flag_value(flag)

func _execute(ctx:Context):
	var search_term = positional_args[0]
	
	if dir_flag == "":
		dir_flag = "res://"
	
	elif not DirAccess.dir_exists_absolute(dir_flag):
		ctx.append_error("Directory doesn't exist: " + dir_flag)
		return ExitCode.FAIL
	
	var prefix = dir_flag if dir_flag.ends_with("/") else dir_flag + "/"
	for f in Utils.file_paths(ctx):
		if not f.begins_with(prefix):
			continue
		if content_flag:
			if not f.get_extension() in _READABLE_EXTS:
				continue
			var file_as_string = FileAccess.get_file_as_string(f)
			if file_as_string.contains(search_term):
				ctx.append_output(f)
		elif search_term.is_subsequence_ofn(f):
			ctx.append_output(f)
	
	return ExitCode.OK

