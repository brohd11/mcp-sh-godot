extends RefCounted
## Preloads the tree namespace and its commands, so exporters that follow preloads include
## them. Load the namespace with ctx.load(Manifest.resource_path.get_base_dir().path_join("tree.gd")).

const TREE = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/tree.gd")

const COMMANDS = [
	TREE,
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/add/add.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/attach/attach.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/duplicate/duplicate.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/free/free.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/group/group.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/index/index.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/inspect/inspect.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/instance/instance.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/nodes/nodes.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/pack/pack.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/parent/parent.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/prop/prop.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/rename/rename.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/reparent/reparent.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/root/root.gd"),
]

