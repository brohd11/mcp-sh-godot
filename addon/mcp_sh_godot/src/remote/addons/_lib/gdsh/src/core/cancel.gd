extends RefCounted
## Cancel state shared by every ctx of one run, so cancel() anywhere stops the whole pipeline.
## Nothing times out unless a host sets a deadline: console commands may run for a long time.
## Long loops call `await ctx.checkpoint()`, which also yields a frame now and then so the
## editor, a console's Ctrl+C and the bridge keep running while the command works.

const Types = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/types.gd")
## Longest a command runs between frames when it calls checkpoint().
const YIELD_MS = 50

var reason:String = ""
var code:int = Types.ExitCode.CANCELLED
## Absolute Time.get_ticks_msec() deadline; 0 means none.
var deadline_ms:int = 0
## Polled at checkpoints; returns a reason to cancel ("" to go on), e.g. the client hung up.
var check:Callable
## Output bytes allowed for the run; 0 means no limit.
var max_output:int = 0
var output_bytes:int = 0
## Above 0 while a `$(...)` body runs: it must finish in the current frame, so checkpoints
## don't yield there, but still poll `check` and the deadline.
var sync_depth:int = 0
var _reported := false
var _last_yield:int = Time.get_ticks_msec()


func cancel(why:String = "cancelled", status:int = Types.ExitCode.CANCELLED) -> void:
	if reason.is_empty():
		reason = why
		code = status


func is_cancelled() -> bool:
	if not reason.is_empty():
		return true
	if deadline_ms > 0 and Time.get_ticks_msec() >= deadline_ms:
		cancel("timed out", Types.ExitCode.TIMEOUT)
		return true
	return false


## True once cancelled. Every YIELD_MS it polls `check` and waits one process frame.
func checkpoint() -> bool:
	if is_cancelled():
		return true
	if Time.get_ticks_msec() - _last_yield < YIELD_MS:
		return false
	if check.is_valid():
		var why = check.call()
		if why is String and not why.is_empty():
			cancel(why)
			return true
	if sync_depth == 0:
		var loop = Engine.get_main_loop()
		if loop is SceneTree:
			await loop.process_frame
	_last_yield = Time.get_ticks_msec()
	return is_cancelled()


## Count streamed output; false (and cancelled) once it passes max_output.
func add_output(bytes:int) -> bool:
	if max_output <= 0:
		return true
	output_bytes += bytes
	if output_bytes > max_output:
		cancel("output limit of %d bytes reached" % max_output, Types.ExitCode.FAIL)
		return false
	return true


## Reported already: a session running input directly takes a fresh token next time.
func is_spent() -> bool:
	return _reported


## The one "cancelled: ..." line for a run, or "" once already given.
func take_report() -> String:
	if reason.is_empty() or _reported:
		return ""
	_reported = true
	return "cancelled: " + reason

