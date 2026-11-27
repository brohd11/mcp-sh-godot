extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const ConvertUtil = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/data/src/convert_util.gd")

const _HELP = \
"Convert a YAML, JSON or binary file to JSON (written as .json unless a write path is given).
Usage: data to_json [--overwrite] [--no-scan] [--from-bin] " + ConvertUtil.USAGE_TAIL

var _convert = ConvertUtil.new("json")

static func get_command_name():
	return "to_json"

static func get_self_command_data():
	return _command_data(ConvertUtil.command_params(_HELP))

func _get_flags() -> Dictionary:
	var options = Options.new()
	ConvertUtil.add_flags(options)
	return options.get_options()

func _process_flag(flag:String):
	_convert.process_flag(flag)

func _execute(ctx:Context):
	return _convert.execute(self, ctx)

