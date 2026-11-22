extends RefCounted
## Preloads the tree namespace and its commands, so exporters that follow preloads include
## them. GDSh.Load skips this file. Register the commands by adding this directory (cmd/) as a
## command folder: host.add_command_dir(Manifest.resource_path.get_base_dir()).

const TREE = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/cmd/tree/tree.gd")

const NAMESPACES = [TREE]

const COMMANDS = [
	TREE,
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/cmd/tree/add/add.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/cmd/tree/attach/attach.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/cmd/tree/call/call.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/cmd/tree/duplicate/duplicate.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/cmd/tree/free/free.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/cmd/tree/group/group.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/cmd/tree/index/index.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/cmd/tree/inspect/inspect.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/cmd/tree/instance/instance.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/cmd/tree/nodes/nodes.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/cmd/tree/pack/pack.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/cmd/tree/parent/parent.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/cmd/tree/prop/prop.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/cmd/tree/rename/rename.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/cmd/tree/reparent/reparent.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/cmd/tree/root/root.gd"),
]

