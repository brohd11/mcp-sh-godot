extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"


const _HELP = \
"Reload the passed scripts resources
Usage: resource reload_script <path> - Can also pass paths as stdin, will be split by newlines."

static func get_command_name() -> String:
	return "reload_script"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
	})

func _get_target_positional_count() -> int:
	if _ctx_obj.stdin == "":
		return 1
	return 0

func _execute(ctx:Context):
	var paths = []
	if positional_args.size() == 1:
		paths.append(positional_args[0])
	else:
		paths = ctx.stdin.split("\n", false)
	
	for p in paths:
		var script = load(p)
		if not script is Script:
			ctx.append_error("Resource not a script: " + p)
			continue
		# load() (and even CACHE_MODE_REPLACE) serve the editor's cached GDScript,
		# which is not refreshed from disk while the editor is unfocused. Re-read the
		# source explicitly so reload() recompiles the on-disk version; live instances
		# hold this same script object, so they rebind.
		if FileAccess.file_exists(p):
			script.source_code = FileAccess.get_file_as_string(p)
		script.reload(true)
		ctx.append_output("Reloaded script: " + p)
	return ExitCode.OK

