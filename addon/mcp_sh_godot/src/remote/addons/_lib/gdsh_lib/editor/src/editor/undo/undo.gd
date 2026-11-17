extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Undo the last action(s) in the edited scene's history, or the global history with --global.
Usage: editor undo [count] [--global]"

var global_flag := false

static func get_command_name() -> String:
	return "undo"

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

## The edited scene's history, or the global one; null after reporting why.
## EditorUndoRedoManager has no undo/redo of its own, so commands work on the history's UndoRedo.
static func get_history(ctx:Context, global:bool) -> UndoRedo:
	var manager = EditorInterface.get_editor_undo_redo()
	if global:
		return manager.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	var edited_root = EditorInterface.get_edited_scene_root()
	if not is_instance_valid(edited_root):
		ctx.append_error("No edited scene open (use --global for the global history).")
		return null
	return manager.get_history_undo_redo(manager.get_object_history_id(edited_root))

## The optional count argument (default 1), or -1 after reporting an invalid one.
static func get_count(ctx:Context, args:Array) -> int:
	if args.is_empty():
		return 1
	if not args[0].is_valid_int() or args[0].to_int() < 1:
		ctx.append_error("Count must be a positive integer: " + args[0])
		return -1
	return args[0].to_int()

func _execute(ctx:Context):
	var count = get_count(ctx, positional_args)
	if count < 1:
		return ExitCode.FAIL
	var history = get_history(ctx, global_flag)
	if history == null:
		return ExitCode.FAIL

	var done := 0
	while done < count and history.has_undo():
		var action_name = history.get_current_action_name()
		history.undo()
		ctx.append_output("Undo: " + action_name)
		done += 1
	if done == 0:
		ctx.append_error("Nothing to undo.")
		return ExitCode.FAIL
	return ExitCode.OK

