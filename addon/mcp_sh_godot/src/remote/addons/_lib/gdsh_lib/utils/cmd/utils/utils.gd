extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"
## Discovery namespace for the package's commands, which load top-level but non-discoverable.
## Lives in its own dir so no loose command in cmd/ claims the whole package as children;
## its children are the `name/name.gd` dirs one level up instead of beside it.

const _HELP = "Portable utilities, also accessible directly by name."


static func get_command_name() -> String:
	return "utils"


static func get_self_command_data() -> Dictionary:
	return _command_data({&"help": _HELP})


func _get_commands() -> Dictionary:
	var cmd_dir = get_script().resource_path.get_base_dir().get_base_dir()
	var scopes = Utils.get_loader().load_directory(cmd_dir, true)
	scopes.erase(get_command_name())
	var options = {}
	for scope in scopes.values():
		Options.add_command_script_to_dict(scope[Types.ScopeDataKeys.SCRIPT], options)
	return Utils.sort_dict_with_priority_key(options, &"priority")


func _execute(ctx:Context):
	ctx.append_output(get_help_string(true))
	return ExitCode.OK

