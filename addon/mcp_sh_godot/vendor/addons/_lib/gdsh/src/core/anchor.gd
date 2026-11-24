extends RefCounted
## Where this gdsh copy landed. Runtime load() paths can't be relative (Godot reads them from
## res://), so lazy loads go through path() instead of a literal: a copy loaded from outside
## res:// (the gdsh CLI's relative export in ~/.gdsh/cli) then finds its own files.

static var _root := ""


## The gdsh dir, with a trailing slash: res://addons/_lib/gdsh/ in a project.
static func root() -> String:
	if _root.is_empty():
		# new(): a static func has no get_script(), and a bare preload names the class, not the resource.
		_root = new().get_script().resource_path.trim_suffix("src/core/anchor.gd")
	return _root


## rel (e.g. "src/core/execute.gd") inside this copy.
static func path(rel:String) -> String:
	return root().path_join(rel)

