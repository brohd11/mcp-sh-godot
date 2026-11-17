extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const StrUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/str_util.gd")

const _HELP = \
"Field of a string split by a delimiter.
Negative indexes count from the end; an index out of range prints an empty line.
Usage: str slice <delimiter> <index> [text]"


static func get_command_name() -> String:
	return "slice"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:2,max:3",
	})


func _execute(ctx:Context):
	var delimiter = positional_args[0]
	if delimiter == "":
		ctx.append_error("Delimiter must not be empty.")
		return ExitCode.FAIL
	if not positional_args[1].is_valid_int():
		ctx.append_error("Index must be an integer: " + positional_args[1])
		return ExitCode.FAIL
	var fn = _field.bind(delimiter, positional_args[1].to_int())
	return StrUtil.map_lines(ctx, StrUtil.inputs(ctx, positional_args, 2), fn)


static func _field(text:String, delimiter:String, index:int) -> String:
	var parts = text.split(delimiter)
	if index < 0:
		index += parts.size()
	return parts[index] if index >= 0 and index < parts.size() else ""

