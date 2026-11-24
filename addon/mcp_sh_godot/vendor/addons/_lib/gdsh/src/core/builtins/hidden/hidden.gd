extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"
## Discover and route to every hidden command registered in the current context.

const Execution = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/execute.gd")

const _HELP = "Hidden commands, also accessible directly by name."


static func get_command_name() -> String:
	return "hidden"


static func get_self_command_data() -> Dictionary:
	return _command_data({&"help": _HELP})


## Children are the context's discoverable hidden scopes, keyed by registered name, so
## hosts and runtime registrations are listed without a directory of their own.
## Non-discoverable commands are reached through their namespace, e.g. `hidden builtins echo`.
func _get_commands() -> Dictionary:
	var commands = {}
	if _ctx_obj == null:
		return commands
	var names = _ctx_obj.scopes_hidden.keys()
	names.sort()
	for name in names:
		if str(name).begins_with("__") or name == get_command_name() \
				or not Utils.is_discoverable(_ctx_obj.scopes_hidden[name]):
			continue
		var command = _ctx_obj.scopes_hidden[name].get(Types.ScopeDataKeys.SCRIPT)
		if command == null or not (command is GDScript or command.has_method("get_self_command_data")):
			continue
		var data = command.get_self_command_data().duplicate()
		data[&"get_command"] = func(): return Execution._instance(command)
		commands[name] = data
	return Utils.sort_dict_with_priority_key(commands, &"priority")


func _execute(ctx:Context):
	ctx.append_output(get_help_string(true))
	return ExitCode.OK

