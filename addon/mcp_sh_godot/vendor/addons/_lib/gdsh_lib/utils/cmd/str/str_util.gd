extends RefCounted
## Shared helpers for str commands. Operands come first, then an optional text argument;
## without that text an op runs on each stdin line, so a pipeline maps line for line.
## ctx is duck-typed and nothing preloads gdsh, so a command rebuilt against another gdsh copy
## (~/.gdsh, the CLI bundle) can still use this.

## gdsh's ExitCode.OK / FAIL.
const _OK = 0
const _FAIL = 1

const NO_INPUT = "No input (argument or stdin)."


## The text argument after operand_count operands, else the stdin lines.
static func inputs(ctx, args:Array[String], operand_count:int) -> PackedStringArray:
	if args.size() > operand_count:
		return PackedStringArray([args[operand_count]])
	return ctx.stdin.split("\n", false)


## Prints fn(line) for each input. Empty results still print a line (write_output keeps them,
## where append_output would drop them), so output lines stay aligned with input lines.
static func map_lines(ctx, lines:PackedStringArray, fn:Callable) -> int:
	if lines.is_empty():
		ctx.append_error(NO_INPUT)
		return _FAIL
	for line in lines:
		ctx.write_output(str(fn.call(line)) + "\n")
	return _OK


## Prints the inputs pred accepts, or nothing when bool_only. OK if any input matched.
static func filter_lines(ctx, lines:PackedStringArray, pred:Callable, bool_only:bool) -> int:
	var matched := false
	for line in lines:
		if not pred.call(line):
			continue
		matched = true
		if bool_only:
			break
		ctx.write_output(line + "\n")
	return _OK if matched else _FAIL

