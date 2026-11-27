extends RefCounted
## Shared body of `data to_json|to_yaml|to_bin`. Each command extends CommandBase itself (a user
## command can't share a base) and forwards its flags and _execute here. The command is
## duck-typed, so this never preloads gdsh and works against whichever copy runs it.

const DataConvert = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/data/src/data_convert.gd")

const USAGE_TAIL = \
"<data file> [write path], or data file paths one per stdin line (written beside each).
JSON and YAML are read by extension; pass --from-bin for a Godot binary (store_var) file."

var format := ""
var bin_ext := "bin"

var overwrite_flag := false
var no_scan_flag := false
var from_bin_flag := false


func _init(output_format:String) -> void:
	format = output_format


## The params for a command's get_self_command_data().
static func command_params(help:String) -> Dictionary:
	return {
		&"help": help,
		&"positional_count": "max: 2",
		&"allow_positional_paths": true,
	}


## Adds the shared flags to a command's Options.
static func add_flags(options) -> void:
	options.add_option("--overwrite", {
		&"help": "Overwrite an existing output file."
	})
	options.add_option("--no-scan", {
		&"help": "Don't rescan the editor FileSystem after writing."
	})
	options.add_option("--from-bin", {
		&"help": "Read the input as Godot binary (root must be a Dictionary or Array)."
	})


func process_flag(flag:String) -> void:
	if flag == "--overwrite":
		overwrite_flag = true
	elif flag == "--no-scan":
		no_scan_flag = true
	elif flag == "--from-bin":
		from_bin_flag = true


func execute(cmd, ctx) -> int:
	var args:Array = cmd.positional_args
	var pairs = [] # [input, output]
	if args.size() == 2:
		pairs.append([cmd.complete_path(args[0]), cmd.complete_path(args[1])])
	else:
		var inputs = args if args.size() == 1 else Array(ctx.stdin.split("\n", false))
		if inputs.is_empty():
			ctx.append_error("Need a data file path (argument or stdin).")
			return cmd.ExitCode.ERR
		for path in inputs:
			var input = cmd.complete_path(path.strip_edges())
			pairs.append([input, DataConvert.default_output(input, format, bin_ext)])

	var status = cmd.ExitCode.OK
	var wrote = false
	for pair in pairs:
		var problem = _convert(pair[0], pair[1])
		if problem.is_empty():
			wrote = true
			ctx.append_output("File converted: %s -> %s" % [pair[0], pair[1].get_file()])
		else:
			ctx.append_error(problem)
			status = cmd.ExitCode.FAIL
	if wrote and not no_scan_flag and Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	return status


## An error message, or "" once `output` is written.
func _convert(input:String, output:String) -> String:
	if format != "bin" and DataConvert.format_of(input) == format:
		return "File already %s: %s" % [format, input]
	if FileAccess.file_exists(output) and not overwrite_flag:
		return "File already exists (pass --overwrite): " + output
	var read = DataConvert.read(input, from_bin_flag)
	if read.has("error"):
		return read.error
	return DataConvert.write(read.data, output, format)

