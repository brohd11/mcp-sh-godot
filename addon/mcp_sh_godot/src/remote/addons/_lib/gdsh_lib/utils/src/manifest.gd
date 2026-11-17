extends RefCounted
## Preloads every command in this directory, so exporters that follow preloads include
## them. GDSh.Load.load_directory skips this file. Load the commands with
## GDSh.Load.load_directory(Manifest.resource_path.get_base_dir()).

const COMMANDS = [
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/utils.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/cat/cat.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/check/check.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/class/class.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/count/count.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/find/find.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/grep/grep.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/head/head.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/ls/ls.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/math/math.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/mkdir/mkdir.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/mv/mv.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/open/open.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/pwd/pwd.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/realpath/realpath.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/scan/scan.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/str.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/tail/tail.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/trash/trash.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/xargs/xargs.gd"),
]

## Subcommands of the `str` namespace. Kept apart from COMMANDS, which mirrors the
## top-level load; load_directory finds these through str.gd.
const STR_COMMANDS = [
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/basedir/basedir.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/basename/basename.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/begins_with/begins_with.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/contains/contains.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/ends_with/ends_with.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/extension/extension.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/file/file.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/join/join.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/length/length.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/lower/lower.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/replace/replace.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/slice/slice.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/strip_edges/strip_edges.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/trim_prefix/trim_prefix.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/trim_suffix/trim_suffix.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/str/upper/upper.gd"),
]

