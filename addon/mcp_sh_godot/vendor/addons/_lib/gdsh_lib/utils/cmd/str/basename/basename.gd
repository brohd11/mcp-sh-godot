extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const StrUtil = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/utils/cmd/str/str_util.gd")

const _HELP = \
"Last component of a path, as Unix basename: res://a/b.gd -> b.gd, res://a/b/ -> b.
With --gd, Godot's String.get_basename instead: the path without its extension (res://a/b).
Usage: str basename [--gd] [text]"

var gd_flag := false


static func get_command_name() -> String:
	return "basename"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:0,max:1",
	})


func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--gd", {&"help": "Use String.get_basename: drop the extension, keep the directory."})
	return options.get_options()


func _execute(ctx:Context):
	var fn = func(s:String): return s.get_basename() if gd_flag else unix_basename(s)
	return StrUtil.map_lines(ctx, StrUtil.inputs(ctx, positional_args, 0), fn)


## A bare root (res://, /) has no component to take, so it comes back unchanged.
static func unix_basename(path:String) -> String:
	while path.ends_with("/") and not path.ends_with("://") and path != "/":
		path = path.left(-1)
	if path.ends_with("://") or path == "/":
		return path
	return path.get_file()

