extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const MatchUtil = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/utils/cmd/str/match_util.gd")

const _HELP = \
"Keep inputs that begin with a prefix; -b only sets the exit code.
Quote a prefix that starts with '-'.
Usage: str begins_with [-b] [-i] <prefix> [text]"


static func get_command_name() -> String:
	return "begins_with"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:1,max:2",
	})


var _match = MatchUtil.new()


func _get_flags() -> Dictionary:
	var options = Options.new()
	MatchUtil.add_flags(options)
	return options.get_options()


func _process_flag(flag:String):
	_match.process_flag(flag)


func _execute(ctx:Context):
	return _match.execute(self, ctx, func(text:String, needle:String): return text.begins_with(needle))

