extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"
## Group the undo actions of many commands into one entry. The buffer is
## `ctx.host_data["undo_session"]`; the undo object comes from `host_data["undo_redo"]`.

const _HELP = \
"Group the undoable changes of several commands into one undo entry.
Changes still apply as each command runs; commit registers them as a single action.
Compounds nest: only the outermost commit registers. While a compound is open, buffered
nodes stay referenced, and edits made outside the console land before its entry.
Usage:
  undoredo                        show whether a compound is open
  undoredo --compound [name]      start (or nest) a compound action
  undoredo commit [name]          close one level; the outermost registers the action
  undoredo cancel                 revert every buffered change and close the compound"

const _DEFAULT_NAME = "Compound action"

var compound_flag := false


static func get_command_name() -> String:
	return "undoredo"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": "min:0,max:2",
	})


func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--compound", {&"help": "Start a compound action, optionally named."})
	return options.get_options()


func _execute(ctx:Context):
	var session = ctx.get_undo_session()
	if session == null:
		ctx.append_error("undoredo: no undo session in this context")
		return ExitCode.FAIL

	if compound_flag:
		if positional_args.size() > 1:
			ctx.append_error("Usage: undoredo --compound [name]")
			return ExitCode.FAIL
		session.begin(positional_args[0] if not positional_args.is_empty() else _DEFAULT_NAME)
		ctx.append_output(_status(session))
		return ExitCode.OK

	if positional_args.is_empty():
		ctx.append_output(_status(session))
		return ExitCode.OK

	match positional_args[0]:
		"commit":
			if not session.is_open():
				ctx.append_error("undoredo: no compound action is open")
				return ExitCode.FAIL
			var count = session.change_count()
			var action_name = positional_args[1] if positional_args.size() > 1 else ""
			var undo_redo = ctx.get_undo_redo()
			if not session.commit(undo_redo, action_name):
				ctx.append_output(_status(session))
			elif count == 0:
				ctx.append_output("Compound closed with no changes.")
			elif is_instance_valid(undo_redo):
				ctx.append_output("Committed '%s': %s change(s)." % [session.name, count])
			else:
				ctx.append_output("Applied %s change(s) without undo." % count)
			return ExitCode.OK
		"cancel":
			if positional_args.size() > 1:
				ctx.append_error("Usage: undoredo cancel")
				return ExitCode.FAIL
			if not session.is_open():
				ctx.append_error("undoredo: no compound action is open")
				return ExitCode.FAIL
			var count = session.change_count()
			session.cancel()
			ctx.append_output("Reverted %s change(s)." % count)
			return ExitCode.OK
	ctx.append_error("undoredo: expected 'commit' or 'cancel', got '%s'" % positional_args[0])
	return ExitCode.FAIL


static func _status(session) -> String:
	if not session.is_open():
		return "No compound action open."
	return "Compound '%s' open: depth %s, %s change(s)." % [session.name, session.depth, session.change_count()]

