extends RefCounted
## Shared helpers for tree commands. Commands read absolute node paths from stdin, one per
## line, and print absolute paths, so every pipeline stage resolves them the same way.
## Undo goes through GDSh core: ctx.host_data["undo_redo"] and `undoredo --compound`.

const Context = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/context.gd")
const NodePaths = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/node_paths.gd")


static func get_tree_root() -> Window:
	return NodePaths.root()


static func path_of(node:Node) -> String:
	return NodePaths.path_of(node)


## Nodes named by the absolute paths on stdin. Bad lines are reported and skipped; empty
## stdin is reported too, so callers only need to fail on an empty result. Absolute-only
## validation stays here; core NodePaths also supports paths relative to a working node.
static func resolve_targets(ctx:Context) -> Array:
	var nodes := []
	if ctx.stdin.strip_edges() == "":
		ctx.append_error("No node paths on stdin (start a chain with 'tree root').")
		return nodes
	for line in ctx.stdin.split("\n", false):
		var p = line.strip_edges()
		if p == "":
			continue
		if not NodePath(p).is_absolute():
			ctx.append_error("Not an absolute node path: " + p)
			continue
		var node = NodePaths.resolve(p)
		if is_instance_valid(node):
			nodes.append(node)
		else:
			ctx.append_error("Node not found: " + p)
	return nodes


## Owner for a new child of parent: the parent's scene root, or the parent when it has no
## owner (a scene root itself).
static func owner_for(parent:Node) -> Node:
	return parent.owner if is_instance_valid(parent.owner) else parent


## Node and its descendants, depth first.
static func walk(node:Node) -> Array:
	var out := []
	_walk(node, out)
	return out


static func _walk(node:Node, out:Array) -> void:
	out.append(node)
	for child in node.get_children():
		_walk(child, out)


## One undoable action per command, committed to the host's undo object when there is one.
static func action(ctx:Context, name:String) -> Context_Undo.Action:
	return ctx.undo_action(name)



### GDPackage Global Classes
const Context_Undo = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/undo.gd")

