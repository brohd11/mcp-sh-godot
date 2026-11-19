extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const ErrorCapture = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/util_r/src/object/error_capture.gd")

const _HELP = \
"Validate that a script or scene loads, reporting 'path: OK' or 'path: ERROR (...)'.
Path comes from the argument or from stdin (one per line, pipeable). Any failure
sets a non-zero exit code. A failing script is followed by its errors, one per
line as 'file:line: message' (Godot 4.5+; earlier versions show them in Output).
Scripts are checked as the file is now, even when an older version is loaded.
Usage: check [path]   |   ... | check"

static func get_command_name() -> String:
	return "check"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": "min:0,max:1",
		&"allow_positional_paths": true,
	})

func _execute(ctx:Context):
	var paths := _gather_paths(ctx)
	if paths.is_empty():
		ctx.append_error("No path provided (pass an argument or pipe paths via stdin).")
		return ExitCode.FAIL

	var any_failed := false
	for path in paths:
		var result := _check_one(path)
		if not result.ok:
			any_failed = true
			ctx.append_output(path + ": ERROR (" + result.message + ")")
			for line in result.get("errors", PackedStringArray()):
				ctx.append_output("  " + line)
		else:
			ctx.append_output(path + ": OK")

	return ExitCode.FAIL if any_failed else ExitCode.OK

func _gather_paths(ctx:Context) -> Array:
	var paths := []
	if not positional_args.is_empty():
		paths.append(positional_args[0].strip_edges())
	elif ctx.stdin.strip_edges() != "":
		for line in ctx.stdin.split("\n", false):
			var p = line.strip_edges()
			if p != "":
				paths.append(p)
	return paths

func _check_one(path:String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "message": "file not found"}

	var ext := path.get_extension().to_lower()
	if ext == "gd":
		# A copy is compiled from the file so edits are checked, not the loaded version. It gets
		# the real path so class_name and relative preloads resolve as for the real script. But
		# GDScript caches the first script compiled under a path, for good, so the real script is
		# loaded first: the copy must never become what the path loads.
		ResourceLoader.load(path, "GDScript") # Cached by GDScript, also when it has errors.
		var script := GDScript.new()
		script.source_code = FileAccess.get_file_as_string(path)
		script.set_path_cache(path)
		var compiled = ErrorCapture.run(script.reload)
		if compiled.result != OK:
			return {"ok": false, "message": error_string(compiled.result), "errors": compiled.errors}
		return {"ok": true, "message": ""}

	# Scenes / resources: confirm the loader can produce a valid resource.
	var res = load(path)
	if not is_instance_valid(res):
		return {"ok": false, "message": "load() returned null"}
	return {"ok": true, "message": ""}

