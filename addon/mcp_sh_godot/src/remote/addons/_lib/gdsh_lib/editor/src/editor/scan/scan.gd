extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Rescan the project filesystem (picks up files added/removed outside the editor).
Usage: editor scan [--focus]"

var focus_flag := false

static func get_command_name() -> String:
	return "scan"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--focus", {
		&"help": "Also grab the editor window's focus when it is unfocused. This triggers the editor's focus-in reload, which reimports changed scripts AND rebinds their live instances (a plain scan does neither). Note: steals OS focus from your current window.",
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--focus":
		focus_flag = true

func _execute(ctx:Context):
	var fs = EditorInterface.get_resource_filesystem()
	if not is_instance_valid(fs):
		ctx.append_error("Could not access the resource filesystem.")
		return ExitCode.FAIL
	# Grab focus first (opt-in): only the main window exposes has_focus(), so if a
	# sub-window is focused this still reports false — harmless, since we always scan
	# below regardless. scan() while a scan is in progress is a no-op.
	if focus_flag:
		var window = EditorInterface.get_base_control().get_window()
		if not window.has_focus():
			window.grab_focus()
			ctx.append_output("Editor window focus grabbed.")
	fs.scan()
	ctx.append_output("Filesystem rescan started.")

