extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/data/src/convert_command.gd"

const _HELP = \
"Convert a JSON or YAML file to Godot binary (FileAccess.store_var), written as .bin or --ext.
Usage: data to_bin [--ext=EXT] [--overwrite] [--no-scan] [--from-bin] " + USAGE_TAIL

static func get_command_name():
	return "to_bin"

static func get_self_command_data():
	return _convert_command_data(_HELP)

func _init() -> void:
	format = "bin"

func _get_flags() -> Dictionary:
	var options = super()
	options.merge(_ext_option())
	return options

func _process_flag(flag:String):
	if flag.begins_with("--ext="):
		bin_ext = _get_flag_value(flag).trim_prefix(".")
	else:
		super(flag)

static func _ext_option() -> Dictionary:
	var options = Options.new()
	options.add_option("--ext=", {
		&"help": "Output extension (default: bin).",
		&"trailing_char": "",
	})
	return options.get_options()

