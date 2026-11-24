extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"List the resource dependencies of a file (one path per line, pipeable).
Usage: resource deps <res://path>"

static func get_command_name() -> String:
	return "deps"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": 1,
	})

func _execute(ctx:Context):
	var path = positional_args[0]
	if not FileAccess.file_exists(path):
		ctx.append_error("File does not exist: " + path)
		return ExitCode.FAIL

	var deps = ResourceLoader.get_dependencies(path)
	if deps.is_empty():
		ctx.append_output("No dependencies.")
		return ExitCode.OK

	for entry in deps:
		ctx.append_output(_resolve_path(entry))
	return ExitCode.OK

func _resolve_path(entry:String) -> String:
	# Entries look like "uid://...::Type::res://path" (order varies by version).
	var res_path := ""
	var uid_path := ""
	for part in entry.split("::"):
		if part.begins_with("res://"):
			res_path = part
		elif part.begins_with("uid://"):
			uid_path = part
	if res_path != "":
		return res_path
	if uid_path != "":
		var id = ResourceUID.text_to_id(uid_path)
		if id != -1 and ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
		return uid_path
	return entry

