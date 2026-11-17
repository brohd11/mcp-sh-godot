extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const Undo = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/undo/undo.gd")

const _HELP = \
"Redo the next action(s) in the edited scene's history, or the global history with --global.
Usage: editor redo [count] [--global]"

var global_flag := false

static func get_command_name() -> String:
	return "redo"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:0,max:1",
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--global", {
		&"help": "Use the global history (project settings and other non-scene edits)."
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--global":
		global_flag = true

func _execute(ctx:Context):
	var count = Undo.get_count(ctx, positional_args)
	if count < 1:
		return ExitCode.FAIL
	var history = Undo.get_history(ctx, global_flag)
	if history == null:
		return ExitCode.FAIL

	var done := 0
	while done < count and history.has_redo():
		history.redo()
		ctx.append_output("Redo: " + history.get_current_action_name())
		done += 1
	if done == 0:
		ctx.append_error("Nothing to redo.")
		return ExitCode.FAIL
	return ExitCode.OK

