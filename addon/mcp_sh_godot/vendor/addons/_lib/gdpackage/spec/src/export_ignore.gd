
@tool
extends RefCounted
## The dev-only folder beside a plugin's source: export config, pre/post script, docs, exports.
## Both spellings are accepted - `_export_ignore` sorts apart from a plugin's real folders and wins
## when a plugin has both. No preloads, so export and release code can share it.

const NAMES = ["_export_ignore", "export_ignore"] # preference order
const DEFAULT_NAME = "_export_ignore"
const CONFIG_NAMES = ["export.yml", "plugin_export.yml", "plugin_export.yaml", "plugin_export.json"]
const SUB_DIRS = ["doc", "test"] # scaffolded by plugin_init: auto docs, editor console `test`


## Searches both folder spellings; a missing config returns its default creation path.
static func config_path(package_dir:String) -> String:
	if package_dir == "":
		return ""
	for path in candidates(package_dir, CONFIG_NAMES):
		if FileAccess.file_exists(path):
			return path
	return dir_or_default(package_dir).path_join(CONFIG_NAMES[0])


static func is_name(dir_name:String) -> bool:
	return dir_name in NAMES


## The first export-ignore folder that exists in plugin_dir, or "".
static func dir_in(plugin_dir:String) -> String:
	for n in NAMES:
		var dir = plugin_dir.path_join(n)
		if DirAccess.dir_exists_absolute(dir):
			return dir
	return ""


## dir_in(), or where a new one should be created.
static func dir_or_default(plugin_dir:String) -> String:
	var existing = dir_in(plugin_dir)
	return existing if existing != "" else plugin_dir.path_join(DEFAULT_NAME)


## `<dir>/<name>/<rel>` for every name and rel, preferred name first. Matching a file rather than a
## folder means a half-finished rename still finds its config. `dir` may be "" for paths relative
## to a package root.
static func candidates(dir:String, rel_paths:Array) -> Array[String]:
	var out:Array[String] = []
	for n in NAMES:
		for rel in rel_paths:
			var path = String(n).path_join(rel)
			out.append(dir.path_join(path) if dir != "" else path)
	return out


## True for a path inside a top-level export-ignore folder of source_dir.
static func is_inside(path:String, source_dir:String) -> bool:
	var base = source_dir.trim_suffix("/") + "/"
	if not path.begins_with(base):
		return false
	var rel = path.trim_prefix(base)
	return "/" in rel and is_name(rel.get_slice("/", 0))

