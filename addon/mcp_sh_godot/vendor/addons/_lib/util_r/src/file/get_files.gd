

const SELF = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/util_r/src/file/get_files.gd") #! resolve UtilR.Files.GetFiles

const GDIGNORE = ".gdignore"
const GODOT_CACHE_DIR = "res://.godot/"

## Root of the scan. Set by open(), reassignable to reuse one instance.
var search_dir:String = "res://"
## Extensions to keep, matched case-insensitively. Empty keeps every file.
var file_extensions:Array = []
## Emit directories as well as files. Always trailing slash; search_dir itself is not emitted.
var include_dirs:=false
## Include dot-prefixed files and dirs. "Hidden" means dot-prefixed - the res:// convention.
var show_hidden:=false
## Descend into directories containing a .gdignore file.
var enter_gdignore:=false
## Skip res://.godot/. Only has an effect when show_hidden is true.
var ignore_godot_cache:=true
## Absolute directory paths to skip. Trailing slash is normalized, pass either form.
var ignore_dir_paths:Array = []
## Bare directory names to skip at any depth, e.g. ".git".
var ignore_dir_names:Array = []
## Sort directories case-insensitively so output order is deterministic.
var sort_dirs:=false

var _extensions:Dictionary = {}
var _ignore_paths:Dictionary = {}
var _ignore_names:Dictionary = {}
var _filter_extensions:=false


static func open(_search_dir:String) -> SELF:
	var ins = new()
	ins.search_dir = _search_dir
	return ins

## Convenience for the common case - one call, no configuration.
static func scan(_search_dir:String="res://", _file_extensions:Array=[]) -> PackedStringArray:
	var ins = open(_search_dir)
	ins.file_extensions = _file_extensions
	return ins.get_files()


func get_files() -> PackedStringArray:
	var found:= PackedStringArray()
	if not DirAccess.dir_exists_absolute(search_dir):
		return found
	_build_lookups()
	_recur(search_dir, found)
	return found


func _build_lookups() -> void:
	_extensions.clear()
	for e:String in file_extensions:
		_extensions[e.to_lower()] = true
	_filter_extensions = not _extensions.is_empty()

	_ignore_names.clear()
	for n:String in ignore_dir_names:
		_ignore_names[n] = true

	_ignore_paths.clear()
	for d:String in ignore_dir_paths:
		_ignore_paths[_with_slash(d)] = true
	if ignore_godot_cache:
		_ignore_paths[GODOT_CACHE_DIR] = true


func _recur(dir:String, found:PackedStringArray) -> void:
	var dir_access = DirAccess.open(dir)
	if not dir_access:
		return
	# Always list hidden entries so .gdignore is visible without an extra
	# file_exists() call; dotfiles are filtered below instead.
	dir_access.include_hidden = true
	var files = dir_access.get_files()

	if not enter_gdignore and GDIGNORE in files:
		return

	for f:String in files:
		if not show_hidden and f.begins_with("."):
			continue
		if _filter_extensions and not _extensions.has(f.get_extension().to_lower()):
			continue
		found.append(dir.path_join(f))

	var dirs = dir_access.get_directories()
	if sort_dirs:
		dirs = Array(dirs)
		dirs.sort_custom(_compare_no_case)

	for d:String in dirs:
		if not show_hidden and d.begins_with("."):
			continue
		if _ignore_names.has(d):
			continue
		var path = dir.path_join(d) + "/"
		if _ignore_paths.has(path):
			continue
		if include_dirs:
			found.append(path)
		_recur(path, found)


static func _with_slash(path:String) -> String:
	if path.ends_with("/"):
		return path
	return path + "/"

static func _compare_no_case(a:String, b:String) -> bool:
	return a.to_lower() < b.to_lower()

