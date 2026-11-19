extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"
## Namespace for commands on the SceneTree. Children are the sibling `name/name.gd` dirs;
## load this file, not the directory, so they stay under `tree`.

const _HELP = \
"Read and change nodes in the SceneTree. Commands take absolute node paths on stdin, one per line,
and print absolute paths, so a chain starts from a path. /scene is the edited scene root (the
current scene in a game), and nodes inside it print as /scene/...:
  editor scene root | tree nodes --recursive Label | tree prop text Hi
Usage: ... | tree <command>"


static func get_command_name() -> String:
	return "tree"


static func get_self_command_data() -> Dictionary:
	return _command_data({&"help": _HELP})


func _execute(ctx:Context):
	ctx.append_output(get_help_string(true))
	return ExitCode.OK

