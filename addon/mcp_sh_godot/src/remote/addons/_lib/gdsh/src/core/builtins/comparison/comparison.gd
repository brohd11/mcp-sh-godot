extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"


const _HELP = \
"Test/comparison command. Returns exit code.
Usage: [ $VAR ] [ -z $VAR ] [ $VAR == some_val ]"

static func get_command_name():
	return "["

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": "min:2 max:4"
	})

#func _get_target_positional_count() -> int:
	#return max(positional_args.size(), 2)

func _execute(ctx:Context):
	if not positional_args[positional_args.size() - 1] == "]":
		ctx.append_error("[: missing closing ']'")
		return ExitCode.FAIL
	var args := positional_args.slice(0, positional_args.size() - 1)  # drop "]"
	if PRINT_DEBUG:
		print("EVAL ARGS::", args)

	return ExitCode.OK if _eval(args, ctx) else ExitCode.FAIL


func _eval(args: Array, ctx) -> bool:
	if args.size() >= 2 and args[0] == "!":
		return not _eval(args.slice(1), ctx)
	match args.size():
		0: return false                              # [ ]      -> false
		1: return args[0] != ""                      # [ $x ]   -> non-empty
		2: return _unary(args[0], args[1], ctx)      # [ -z $x ]
		3: return _compare(args[0], args[1], args[2], ctx)  # [ $a == $b ]
		_:
			ctx.append_error("[: too many arguments - " + " ".join(args))
			return false

func _compare(left: String, op: String, right: String, ctx) -> bool:
	match op:
		"==", "=": return left == right
		"!=": return left != right
		"-eq", "-ne", "-lt", "-le", "-gt", "-ge":
			if not (left.is_valid_int() and right.is_valid_int()):
				ctx.append_error("[: integer expected")
				return false
			var l := left.to_int()
			var r := right.to_int()
			match op:
				"-eq": return l == r
				"-ne": return l != r
				"-lt": return l < r
				"-le": return l <= r
				"-gt": return l > r
				"-ge": return l >= r
		_:
			ctx.append_error("[: unknown operator '%s'" % op)
			return false
	return false


func _unary(op: String, operand: String, ctx) -> bool:
	match op:
		"-z": return operand == ""     # true if empty
		"-n": return operand != ""     # true if non-empty
		# filesystem tests — only if your shell has a filesystem to test against.
		# Map these to your VFS; Godot's static APIs shown as the likely target.
		"-e": return FileAccess.file_exists(operand) or DirAccess.dir_exists_absolute(operand)
		"-f": return FileAccess.file_exists(operand)
		"-d": return DirAccess.dir_exists_absolute(operand)
		_:
			ctx.append_error("[: unknown unary operator '%s'" % op)
			return false

