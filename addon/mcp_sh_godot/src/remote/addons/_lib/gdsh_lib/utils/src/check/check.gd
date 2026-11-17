extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Validate that a script or scene loads, reporting 'path: OK' or 'path: ERROR (...)'.
Path comes from the argument or from stdin (one per line, pipeable). Any failure
sets a non-zero exit code. Note: GDScript only exposes an error code here, not
per-line parse messages, so detail is limited.
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
		var text := FileAccess.get_file_as_string(path)
		var script := GDScript.new()
		script.source_code = text
		var err := script.reload()
		if err != OK:
			return {"ok": false, "message": error_string(err)}
		return {"ok": true, "message": ""}

	# Scenes / resources: confirm the loader can produce a valid resource.
	var res = load(path)
	if not is_instance_valid(res):
		return {"ok": false, "message": "load() returned null"}
	return {"ok": true, "message": ""}

