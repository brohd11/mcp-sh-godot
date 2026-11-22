extends RefCounted
## Preloads every utils command, so exporters that follow preloads include them. GDSh.Load
## skips this file. Register the commands by adding this directory (cmd/) as a command folder:
## host.add_command_dir(Manifest.resource_path.get_base_dir()). Flat on purpose: the commands
## are top-level (non-discoverable) and utils/utils.gd only lists them.

const COMMANDS = [
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/utils/utils.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/cat/cat.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/check/check.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/class/class.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/count/count.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/find/find.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/grep/grep.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/head/head.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/ls/ls.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/math/math.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/mkdir/mkdir.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/mv/mv.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/open/open.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/pwd/pwd.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/realpath/realpath.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/scan/scan.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/str/str.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/tail/tail.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/trash/trash.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/xargs/xargs.gd"),
]

## Subcommands of the `str` namespace. Kept apart from COMMANDS, which mirrors the
## top-level load; load_directory finds these through str.gd.
const STR_COMMANDS = [
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/str/basedir/basedir.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/str/basename/basename.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/str/begins_with/begins_with.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/str/contains/contains.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/str/ends_with/ends_with.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/str/extension/extension.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/str/file/file.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/str/join/join.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/str/length/length.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/str/lower/lower.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/str/replace/replace.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/str/slice/slice.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/str/strip_edges/strip_edges.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/str/trim_prefix/trim_prefix.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/str/trim_suffix/trim_suffix.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/str/upper/upper.gd"),
]

