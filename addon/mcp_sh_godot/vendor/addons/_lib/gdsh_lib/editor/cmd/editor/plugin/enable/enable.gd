extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"


const _HELP = \
"Enable/disable plugin state.
Usage: editor plugin enable <plugin name> <state>"

var enable_flag:=false
var disable_flag:=false
var toggle_flag:=false


static func get_command_name():
	return "enable"

static func get_self_command_data():
	return _command_data({
		&"help": _HELP,
		&"positional_count": 1
	})

func _get_completions(ctx:Completion):
	var options = Options.new()
	options.merge(_get_flags())
	var valid_dir_arg = positional_args.size() > 0 and DirAccess.dir_exists_absolute("res://addons/".path_join(positional_args[0]))
	if positional_arg_index > 0 or valid_dir_arg:
		if enable_flag or disable_flag or toggle_flag:
			return {}
		return options.get_options()
	for dir in DirAccess.get_directories_at("res://addons/"):
		options.add_option(dir)
	
	return options.get_options()

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--enable", {
		&"help": ""
	})
	options.add_option("--disable", {
		&"help": ""
	})
	options.add_option("--toggle", {
		&"help": "",
	})
	return options.get_options()

func _process_flag(flag:String):
	match flag:
		"--enable": enable_flag = true
		"--disable": disable_flag = true
		"--toggle": toggle_flag = true

func _execute(ctx:Context):
	var flag_count = int(enable_flag) + int(disable_flag) + int(toggle_flag)
	if flag_count > 1:
		ctx.append_error("Cannot provide more than one flag.")
		return ExitCode.ERR
	var enable = enable_flag or flag_count == 0
	var plugin_name = positional_args[0]
	if enable:
		if not _valid_state(ctx, plugin_name, true):
			return ExitCode.FAIL
		EditorInterface.set_plugin_enabled(plugin_name, true)
	elif disable_flag:
		if not _valid_state(ctx, plugin_name, false):
			return ExitCode.FAIL
		EditorInterface.set_plugin_enabled(plugin_name, false)
	elif toggle_flag:
		if not _valid_state(ctx, plugin_name, false):
			return ExitCode.FAIL
		EditorInterface.set_plugin_enabled(plugin_name, false)
		EditorInterface.set_plugin_enabled(plugin_name, true)
	return ExitCode.OK

func _valid_state(ctx:Context, plugin_name:String, target_state:bool):
	if EditorInterface.is_plugin_enabled(plugin_name) == target_state:
		ctx.append_output("Plugin '%s' state already target: %s" % [plugin_name, target_state])
		return false
	return true

