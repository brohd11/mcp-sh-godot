extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Create a new scene file with a root node of the given class, and open it.
Usage: editor scene new <ClassName> <res://dest.tscn>"

var name_flag := ""
var no_open_flag := false

static func get_command_name() -> String:
	return "new"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": 2,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--name=", {
		&"help": "Name for the root node (default: the dest file name).",
		&"trailing_char": "",
	})
	options.add_option("--no-open", {
		&"help": "Create the file but don't open it; print the path (pipeable into 'open')."
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag.begins_with("--name="):
		name_flag = Utils.unquote(_get_flag_value(flag))
	elif flag == "--no-open":
		no_open_flag = true

func _execute(ctx:Context):
	var cls = positional_args[0]
	if not ClassDB.class_exists(cls):
		ctx.append_error("Not a class: " + cls)
		return ExitCode.FAIL
	if not ClassDB.can_instantiate(cls):
		ctx.append_error("Class cannot be instantiated: " + cls)
		return ExitCode.FAIL
	if not ClassDB.is_parent_class(cls, "Node"):
		ctx.append_error("Class is not a Node: " + cls)
		return ExitCode.FAIL

	var dest = positional_args[1]
	if not dest.begins_with("res://"):
		ctx.append_error("Destination must be a res:// path: " + dest)
		return ExitCode.FAIL
	if dest.get_extension() == "":
		dest += ".tscn"
	if FileAccess.file_exists(dest):
		ctx.append_error("File already exists: " + dest)
		return ExitCode.FAIL

	var root:Node = ClassDB.instantiate(cls)
	root.name = name_flag if name_flag != "" else dest.get_file().get_basename()

	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())

	var packed = PackedScene.new()
	var err = packed.pack(root)
	root.free()
	if err != OK:
		ctx.append_error("Pack failed (error %s): %s" % [err, error_string(err)])
		return ExitCode.FAIL
	err = ResourceSaver.save(packed, dest)
	if err != OK:
		ctx.append_error("Save failed (error %s): %s" % [err, error_string(err)])
		return ExitCode.FAIL

	EditorInterface.get_resource_filesystem().update_file(dest)

	if no_open_flag:
		ctx.append_output(dest)
	else:
		EditorInterface.open_scene_from_path(dest)
		ctx.append_output("Created scene: " + dest)
	return ExitCode.OK

