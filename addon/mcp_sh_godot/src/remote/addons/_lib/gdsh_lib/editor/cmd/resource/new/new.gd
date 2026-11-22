extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Create a new resource of a given class and save it.
Usage: resource new <ClassName> <res://dest.tres> [--script=res://x.gd]
The destination path is written to stdout (pipe into 'open')."

var script_flag := ""

static func get_command_name() -> String:
	return "new"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": 2,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--script=", {
		&"help": "Attach a script to the new resource.",
		&"trailing_char": "",
		&"flag_completion": {"type": FlagType.FILE, "ext": ["gd"]},
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag.begins_with("--script="):
		script_flag = _get_flag_value(flag)

func _execute(ctx:Context):
	var type = positional_args[0]
	var dest = positional_args[1]

	if not ClassDB.class_exists(type) or not ClassDB.can_instantiate(type):
		ctx.append_error("Cannot instantiate class: " + type)
		return ExitCode.FAIL
	if not ClassDB.is_parent_class(type, "Resource"):
		ctx.append_error("Class is not a Resource: " + type)
		return ExitCode.FAIL

	var res = ClassDB.instantiate(type)
	if not res is Resource:
		ctx.append_error("Failed to create resource: " + type)
		return ExitCode.FAIL

	if script_flag != "":
		if not FileAccess.file_exists(script_flag):
			ctx.append_error("Script does not exist: " + script_flag)
			return ExitCode.FAIL
		var script = load(script_flag)
		if not script is Script:
			ctx.append_error("Not a script: " + script_flag)
			return ExitCode.FAIL
		res.set_script(script)

	var dest_dir = dest.get_base_dir()
	if not DirAccess.dir_exists_absolute(dest_dir):
		DirAccess.make_dir_recursive_absolute(dest_dir)

	var err = ResourceSaver.save(res, dest)
	if err != OK:
		ctx.append_error("Save failed (error %s): %s" % [err, error_string(err)])
		return ExitCode.FAIL

	EditorInterface.get_resource_filesystem().update_file(dest)
	ctx.append_output(dest)
	return ExitCode.OK

