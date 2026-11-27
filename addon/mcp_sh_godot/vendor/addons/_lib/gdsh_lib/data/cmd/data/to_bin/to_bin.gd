extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const ConvertUtil = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/data/src/convert_util.gd")

const _HELP = \
"Convert a JSON or YAML file to Godot binary (FileAccess.store_var), written as .bin or --ext.
Usage: data to_bin [--ext=EXT] [--overwrite] [--no-scan] [--from-bin] " + ConvertUtil.USAGE_TAIL

var _convert = ConvertUtil.new("bin")

static func get_command_name():
	return "to_bin"

static func get_self_command_data():
	return _command_data(ConvertUtil.command_params(_HELP))

func _get_flags() -> Dictionary:
	var options = Options.new()
	ConvertUtil.add_flags(options)
	options.add_option("--ext=", {
		&"help": "Output extension (default: bin).",
		&"trailing_char": "",
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag.begins_with("--ext="):
		_convert.bin_ext = _get_flag_value(flag).trim_prefix(".")
	else:
		_convert.process_flag(flag)

func _execute(ctx:Context):
	return _convert.execute(self, ctx)

