extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"
## Namespace for string ops. Children are the sibling `name/name.gd` dirs; str_util.gd and
## match_base.gd are shared scripts, not commands.

const _HELP = \
"String ops on one text argument or on each stdin line.
Operands come first, then the optional text; without it the op maps stdin line for line:
  str file res://a/b.gd
  ls -r | str ends_with .gd | str basedir
Predicates (begins_with, ends_with, contains) print the inputs that match, or with -b only
set the exit code:
  if str begins_with -b res:// \"$P\" { echo local }
Usage: str <op> <operands> [text]"


static func get_command_name() -> String:
	return "str"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
	})


func _execute(ctx:Context):
	ctx.append_output(get_help_string(true))
	return ExitCode.OK

