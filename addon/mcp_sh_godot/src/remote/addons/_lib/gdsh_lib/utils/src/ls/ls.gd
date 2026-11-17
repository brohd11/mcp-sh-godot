extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"List files and directories under a project directory (one path per line).
Usage: ls [{path:ctx.cwd}] [--recursive] [--ext=gd] [--dirs] [--full-path]"

var recursive_flag := false
var dirs_flag := false
var ext_flag := ""
var full_path_flag:= false

static func get_command_name() -> String:
	return "ls"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": "min:0,max:1",
		&"allow_positional_paths": true,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--recursive", {
		&"short": "r",
		&"help": "Descend into subdirectories."
	})
	options.add_option("--dirs", {
		&"short": "d",
		&"help": "List directories only."
	})
	options.add_option("--ext=", {
		&"help": "Only list files with this extension.",
		&"trailing_char": "",
	})
	options.add_option("--full-path", {
		&"short": "f",
		&"help": "Display full path instead of file/dir name."
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--recursive":
		recursive_flag = true
	elif flag == "--dirs":
		dirs_flag = true
	elif flag == "--full-path":
		full_path_flag = true
	elif flag.begins_with("--ext="):
		ext_flag = _get_flag_value(flag).lstrip(".")

func _execute(ctx:Context):
	var dir := ctx.cwd
	if not positional_args.is_empty():
		dir = _complete_path(positional_args[0], ctx.cwd)
	dir = ProjectSettings.localize_path(dir)
	if not dir.ends_with("/"):
		dir += "/"
	if not DirAccess.dir_exists_absolute(dir):
		ctx.append_error("Directory does not exist: " + dir)
		return ExitCode.FAIL

	if recursive_flag:
		if dirs_flag:
			for d in Utils.file_paths(ctx, true):
				if d.begins_with(dir):
					if not full_path_flag:
						d = d.trim_prefix(dir)
					ctx.append_output(d)
		else:
			for f in Utils.file_paths(ctx):
				if f.begins_with(dir) and _ext_ok(f):
					if not full_path_flag:
						f = f.trim_prefix(dir)
					ctx.append_output(f)
		return

	for d in DirAccess.get_directories_at(dir):
		ctx.append_output(_process_path(d, dir, true))
	if dirs_flag:
		return
	for f in DirAccess.get_files_at(dir):
		if _ext_ok(f):
			ctx.append_output(_process_path(f, dir, false))

func _ext_ok(path:String) -> bool:
	return ext_flag == "" or path.get_extension() == ext_flag

func _process_path(file_nm:String, parent_dir:String, is_dir:bool):
	if full_path_flag:
		var full_path = parent_dir.path_join(file_nm)
		if is_dir and not full_path.ends_with("/"):
			full_path += "/"
		return full_path
	if is_dir and not file_nm.ends_with("/"):
		file_nm += "/"
	return file_nm

