extends RefCounted
## Shared SceneTree lookup for command-position node targets, the `cwn` working node and
## optional command packs such as gdsh_lib/tree. Callers own their input policy and diagnostics.

## Where `cwn` starts. In the editor this is the editor's own window, not the edited scene;
## a host that knows better sets `cwn` itself.
const DEFAULT_CWN = "/root"
## `/scene` names the edited scene root (editor) or current scene (game), so paths stay short
## and stable. Real absolute paths start with the tree root's name, `root`, so it can't clash.
const SCENE_ALIAS = "scene"
const Options = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/options.gd")
const PathCompletion = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/path_completion.gd")


## The SceneTree root, or null when there is no SceneTree.
static func root() -> Window:
	var loop = Engine.get_main_loop()
	return loop.root if loop is SceneTree else null


## The edited scene root in the editor, the current scene in a game; null when there is none.
## EditorInterface is looked up by name so exported games still parse this file.
static func scene_root() -> Node:
	var node:Node = null
	if Engine.is_editor_hint():
		if Engine.has_singleton(&"EditorInterface"):
			node = Engine.get_singleton(&"EditorInterface").get_edited_scene_root()
	else:
		var loop = Engine.get_main_loop()
		if loop is SceneTree:
			node = loop.current_scene
	return node if is_instance_valid(node) and node.is_inside_tree() else null


## Absolute path of a node, matching the `tree` convention so output pipes into tree commands.
## Nodes in the scene print as `/scene/...`; anything else keeps its full path.
static func path_of(node:Node) -> String:
	var scene = scene_root()
	if scene != null and node.is_inside_tree():
		if node == scene:
			return "/" + SCENE_ALIAS
		if scene.is_ancestor_of(node):
			return "/%s/%s" % [SCENE_ALIAS, scene.get_path_to(node)]
	return str(node.get_path())


## True when an absolute path starts with the `/scene` alias.
static func is_scene_path(node_path:NodePath) -> bool:
	if not node_path.is_absolute() or node_path.get_name_count() == 0:
		return false
	var tree_root = root()
	return node_path.get_name(0) == SCENE_ALIAS and (tree_root == null or tree_root.name != SCENE_ALIAS)


# Absolute lookup that understands `/scene`. Subnames (":prop") are ignored, as get_node does.
static func _get_absolute(tree_root:Node, node_path:NodePath) -> Node:
	if not is_scene_path(node_path):
		return tree_root.get_node_or_null(node_path)
	var scene = scene_root()
	if scene == null:
		return null
	var names := PackedStringArray()
	for i in range(1, node_path.get_name_count()):
		names.append(node_path.get_name(i))
	return scene if names.is_empty() else scene.get_node_or_null(NodePath("/".join(names)))


## The node `cwn` names, falling back to the tree root when it no longer resolves (the scene
## changed, or the node was freed). Null only when there is no SceneTree at all.
static func cwn_node(cwn:String) -> Node:
	var tree_root = root()
	if tree_root == null:
		return null
	if cwn.is_empty():
		return tree_root
	var node = _get_absolute(tree_root, NodePath(cwn))
	return node if is_instance_valid(node) else tree_root


## The node `path` names: absolute paths resolve from the tree root, relative ones from `cwn`
## (so `..` works). Null when nothing is there. Resource paths are never node paths, so they are
## refused before touching the tree — `res://foo.gd` must stay a script, not a node lookup.
static func resolve(path:String, cwn:String=DEFAULT_CWN) -> Node:
	if path.is_empty() or path.contains("://"):
		return null
	var tree_root = root()
	if tree_root == null:
		return null
	var node_path := NodePath(path)
	var node:Node = null
	if node_path.is_absolute():
		node = _get_absolute(tree_root, node_path)
	else:
		var base = cwn_node(cwn)
		if base != null:
			node = base.get_node_or_null(node_path)
	return node if is_instance_valid(node) else null


## Complete the last path segment, retaining the typed prefix for whole-word replacement.
## Internal children are addressable too, and make up much of the editor's SceneTree.
static func complete_path(path:String, cwn:String=DEFAULT_CWN, raw_word:String="", include_internal:bool=true) -> Dictionary:
	var options = Options.new()
	if path.contains(":"):
		return options.get_options()
	var insert_base = path.left(path.rfind("/") + 1)
	if insert_base == "/":
		var tree_root = root()
		if tree_root != null:
			PathCompletion.add_path_option(options, str(tree_root.name), insert_base, raw_word)
		if scene_root() != null:
			PathCompletion.add_path_option(options, SCENE_ALIAS, insert_base, raw_word)
		return options.get_options()
	var base = cwn_node(cwn) if insert_base.is_empty() else resolve(insert_base, cwn)
	if base == null:
		return options.get_options()
	if base.get_parent() != null:
		PathCompletion.add_path_option(options, "..", insert_base, raw_word)
	for child in base.get_children(include_internal):
		PathCompletion.add_path_option(options, str(child.name), insert_base, raw_word)
	return options.get_options()

