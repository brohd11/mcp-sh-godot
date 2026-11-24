
## Collect the errors Godot reports while a callable runs, such as a script's parse errors from
## GDScript.reload(), which otherwise only reach the Output panel. Uses a Logger (Godot 4.5+).
## On older versions the callable still runs and no errors are collected.

## Compiled from source on first use, so this file still parses where Logger doesn't exist.
const _SINK_SOURCE = \
"extends Logger
var _lines := PackedStringArray()
var _mutex := Mutex.new()

# Loggers can be called from any thread, and must not print (that would log again).
func _log_error(function:String, file:String, line:int, code:String, rationale:String, editor_notify:bool, error_type:int, script_backtraces:Array[ScriptBacktrace]) -> void:
	_mutex.lock()
	_lines.append('%s:%d: %s' % [file, line, rationale if not rationale.is_empty() else code])
	_mutex.unlock()

func _log_message(message:String, error:bool) -> void:
	pass

func take() -> PackedStringArray:
	_mutex.lock()
	var lines = _lines
	_lines = PackedStringArray()
	_mutex.unlock()
	return lines
"

static var _sink_script:GDScript = null


## False before Godot 4.5: run() then collects nothing.
static func supported() -> bool:
	return ClassDB.class_exists(&"Logger")


## Run callable and return {result, errors}: its return value, and each error reported meanwhile
## as "file:line: message". Errors from other threads in that time are included too.
static func run(callable:Callable) -> Dictionary:
	var sink = start()
	var result = callable.call()
	return {"result": result, "errors": stop(sink)}


## Start collecting, for callers that await between start and stop. Returns the handle for
## stop(), or null where unsupported.
static func start():
	var sink = _new_sink()
	if sink != null:
		# By name: a direct OS.add_logger() call wouldn't parse before 4.5.
		OS.call(&"add_logger", sink)
	return sink


## Stop collecting and return the errors reported since start(sink).
static func stop(sink) -> PackedStringArray:
	if sink == null:
		return PackedStringArray()
	OS.call(&"remove_logger", sink)
	return sink.take()


static func _new_sink():
	if not supported():
		return null
	if _sink_script == null:
		var script = GDScript.new()
		script.source_code = _SINK_SOURCE
		if script.reload() != OK:
			return null
		_sink_script = script
	return _sink_script.new()

