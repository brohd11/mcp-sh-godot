
## Compile a script file against a base chosen at runtime. `extends` resolves at parse time, so
## the file's extends line is swapped in place (line numbers survive) for the base's path, then
## the source is compiled. Use it when the base lives at a path the file can't know, such as a
## library bundled into whichever plugin is running.
## The body must not override _init (the base's _init logic gets skipped), and the result does
## not hot reload: build again to pick up edits.

const ErrorCapture = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/util_r/src/object/error_capture.gd")

## Why the last build failed, as "file:line: message" lines (empty after a success). Compile
## errors are only collected on Godot 4.5+ (see ErrorCapture); before that they reach the Output.
static var last_errors := PackedStringArray()

## Compile source_path as a script extending `base`. The extends line is swapped only when its
## target ends with `only_if_suffix` (empty: always); otherwise the source compiles as written.
## The result reports errors under, and has the resource_path of, source_path, without entering
## the resource cache, so load() still returns the file itself. Null on error, with last_errors.
static func build(source_path:String, base:Script, only_if_suffix:="") -> GDScript:
	last_errors = PackedStringArray()
	if base == null or base.resource_path.is_empty():
		return _fail(source_path, "no base script with a path")
	if not FileAccess.file_exists(source_path):
		return _fail(source_path, "file not found")
	var source:String = FileAccess.get_file_as_string(source_path)

	# Only the target is replaced: a trailing comment stays, and the line count can't change.
	var found:RegExMatch = RegEx.create_from_string("(?m)^extends[ \\t]+(\"[^\"\\n]*\"|'[^'\\n]*'|[^\\s#]+)").search(source)
	if found == null:
		return _fail(source_path, "no extends line")
	var target:String = found.get_string(1)
	if target.begins_with("\"") or target.begins_with("'"):
		target = target.substr(1, target.length() - 2)
	if only_if_suffix.is_empty() or target.ends_with(only_if_suffix):
		source = source.substr(0, found.get_start(1)) + '"%s"' % base.resource_path + source.substr(found.get_end(1))

	var script:GDScript = GDScript.new()
	script.source_code = source
	script.set_path_cache(source_path)
	var compiled = ErrorCapture.run(script.reload)
	if compiled.result != OK:
		last_errors = compiled.errors
		printerr("ScriptRebase - failed to compile %s (%s)" % [source_path, error_string(compiled.result)])
		return null
	return script


static func _fail(source_path:String, reason:String) -> GDScript:
	last_errors = PackedStringArray(["%s: %s" % [source_path, reason]])
	printerr("ScriptRebase - %s: %s" % [reason, source_path])
	return null

