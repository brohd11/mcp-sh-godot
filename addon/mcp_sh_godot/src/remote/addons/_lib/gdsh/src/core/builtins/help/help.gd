extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"
## List visible and hidden commands in the current execution context.

const _HELP = "List available visible and hidden GDSh commands."


static func get_command_name() -> String:
	return "help"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": 0,
	})


func _execute(ctx:Context) -> void:
	ctx.append_output(_section("Commands", ctx.scopes) + "\n\n" +
			_section("Hidden commands", ctx.scopes_hidden))


static func _section(title:String, values:Dictionary) -> String:
	var names:Array[String] = []
	for name in values:
		var text = str(name)
		if not text.begins_with("__") and Utils.is_discoverable(values[name]):
			names.append(text)
	names.sort()
	if names.is_empty():
		return title + ":\n  (none)"
	return title + ":\n  " + "\n  ".join(names)

