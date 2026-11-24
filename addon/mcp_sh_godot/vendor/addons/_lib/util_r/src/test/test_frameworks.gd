
## Tells GUT and GdUnit4 suites apart by their extends chain, without loading them: the framework
## may be absent (release workspaces), and custom test bases are followed through class_name,
## relative, res:// and uid:// extends. One instance per scan; headers and verdicts are cached.

const StringMap = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/util_r/src/string/string_map.gd") #! resolve UtilR.Strings.StringMap

const GUT = "gut"
const GDUNIT4 = "gdunit4"
const NATIVE = "native"
const NATIVE_SUFFIX = "_test.gd"
const BASE_CLASSES = {"GutTest": GUT, "GdUnitTestSuite": GDUNIT4}
const BASE_PATHS = {"/addons/gut/test.gd": GUT, "/addons/gdUnit4/src/GdUnitTestSuite.gd": GDUNIT4}

## class_name -> script path, for resolving custom bases. Callers may preset it before indexing.
var class_paths:Dictionary = {}
var _headers:Dictionary = {}
var _frameworks:Dictionary = {}


func index_classes(files:Array) -> void:
	_frameworks.clear()
	for path:String in files:
		if path.get_extension() != "gd":
			continue
		var header = _header(path)
		if header.name != "":
			class_paths[header.name] = path


## Fills class_paths from the project's global classes; entries already indexed win.
func index_global_classes() -> void:
	_frameworks.clear()
	for entry in ProjectSettings.get_global_class_list():
		if not class_paths.has(entry.class):
			class_paths[entry.class] = entry.path


## GUT, GDUNIT4, or "" when the file isn't a framework suite.
func framework(path:String) -> String:
	if path.get_extension() != "gd":
		return ""
	if _frameworks.has(path):
		return _frameworks[path]
	_frameworks[path] = "" # also breaks cyclic custom inheritance
	for base:String in BASE_PATHS:
		if path.ends_with(base):
			_frameworks[path] = BASE_PATHS[base]
			return _frameworks[path]
	var header = _header(path)
	if BASE_CLASSES.has(header.base):
		_frameworks[path] = BASE_CLASSES[header.base]
		return _frameworks[path]
	var parent:String = header.path
	if parent == "":
		parent = class_paths.get(header.base, "")
	elif parent.begins_with("uid://"):
		var id = ResourceUID.text_to_id(parent)
		parent = ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else ""
	elif parent.is_relative_path():
		parent = path.get_base_dir().path_join(parent).simplify_path()
	_frameworks[path] = framework(parent) if parent != "" else ""
	return _frameworks[path]


func is_framework_test(path:String) -> bool:
	return framework(path) != ""


## {native: [], gut: [], gdunit4: []}, order kept. Native is a `*_test.gd` that isn't a
## framework suite; other files are dropped.
func split(paths:Array) -> Dictionary:
	var out = {NATIVE: [], GUT: [], GDUNIT4: []}
	for path:String in paths:
		var kind = framework(path)
		if kind != "":
			out[kind].append(path)
		elif path.ends_with(NATIVE_SUFFIX):
			out[NATIVE].append(path)
	return out


func _header(path:String) -> Dictionary:
	if _headers.has(path):
		return _headers[path]
	var header = {"name": "", "base": "", "path": ""}
	_headers[path] = header
	if not FileAccess.file_exists(path):
		return header
	var text = FileAccess.get_file_as_string(path)
	var map = StringMap.new(text, StringMap.Mode.STRING)
	var names = RegEx.new()
	names.compile(r"(?m)^class_name[\t ]+([A-Za-z_]\w*)")
	for found in names.search_all(text):
		if not map.index_in_string_or_comment(found.get_start()):
			header.name = found.get_string(1)
			break
	var bases = RegEx.new()
	bases.compile("(?m)^(?:extends[\\t ]+|class_name[\\t ]+[A-Za-z_]\\w*[\\t ]+extends[\\t ]+)([\"']([^\"'\\n]+)[\"']|[A-Za-z_]\\w*)")
	for found in bases.search_all(text):
		if map.index_in_string_or_comment(found.get_start()):
			continue
		header.path = found.get_string(2)
		if header.path == "":
			header.base = found.get_string(1)
		break
	return header

