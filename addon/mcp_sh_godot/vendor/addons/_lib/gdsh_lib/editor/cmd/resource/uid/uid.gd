extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Convert between a resource path and its uid:// identifier.
Usage:
  uid <res://path>     print the uid:// for the file
  uid <uid://...>      print the res:// path for the uid"

static func get_command_name() -> String:
	return "uid"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": 1,
	})

func _execute(ctx:Context):
	var arg = positional_args[0]

	if arg.begins_with("uid://"):
		var id = ResourceUID.text_to_id(arg)
		if id == -1 or not ResourceUID.has_id(id):
			ctx.append_error("Unknown uid: " + arg)
			return ExitCode.FAIL
		ctx.append_output(ResourceUID.get_id_path(id))
		return ExitCode.OK

	if not FileAccess.file_exists(arg):
		ctx.append_error("File does not exist: " + arg)
		return ExitCode.FAIL
	var id = ResourceLoader.get_resource_uid(arg)
	if id == -1:
		ctx.append_error("No uid associated with: " + arg)
		return ExitCode.FAIL
	ctx.append_output(ResourceUID.id_to_text(id))
	return ExitCode.OK

