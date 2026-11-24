extends RefCounted
## Finds and runs suites (native `*_test.gd`, GUT, GdUnit4) for the `test` command: package
## discovery, target resolution (a cwd dir, else a package name mapped to its export-ignore test
## dir) and file collection. Static and editor-free, so the gdsh CLI and Editor Console share it.

const TestRunner = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/util_r/src/test/test_runner.gd")
const TestFrameworks = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/util_r/src/test/test_frameworks.gd")
const FrameworkRunner = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/test/src/framework_runner.gd")
const GetFiles = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/util_r/src/file/get_files.gd")
const PackageCfg = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdpackage/spec/src/package_cfg.gd")
const ExportIgnore = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdpackage/spec/src/export_ignore.gd")

const TEST_DIR = "test"
const ADDONS = "res://addons/"


## {packages: {name: dir}, ambiguous: {name: [dirs]}} for every package dir under `root` in `dirs`.
## Dirs inside an export-ignore folder (below root) hold export copies with their own cfg, so they're skipped.
static func build_packages(dirs:Array, root:String = ADDONS) -> Dictionary:
	root = root.trim_suffix("/") + "/"
	var found = {"packages": {}, "ambiguous": {}}
	for dir:String in dirs:
		if not dir.begins_with(root):
			continue
		var segments = dir.trim_prefix(root).split("/")
		if ExportIgnore.NAMES.any(func(d): return d in segments):
			continue
		if not PackageCfg.has_cfg(dir):
			continue
		var nm = dir.get_file()
		if found.packages.has(nm):
			found.ambiguous.get_or_add(nm, [found.packages[nm]]).append(dir)
		else:
			found.packages[nm] = dir
	return found


## build_packages over a fresh walk of `root` (hidden and export-ignore dirs pruned). Uncached.
static func find_packages(root:String = ADDONS) -> Dictionary:
	var dirs = []
	_walk(root.trim_suffix("/"), dirs)
	return build_packages(dirs, root)


## The package's test dir, or "". Empty ones don't count, since plugin_init scaffolds the dir.
static func package_test_dir(pkg_dir:String) -> String:
	for ignore in ExportIgnore.NAMES:
		var path = pkg_dir.path_join(ignore).path_join(TEST_DIR)
		if not DirAccess.dir_exists_absolute(path):
			continue
		if DirAccess.get_files_at(path).is_empty() and DirAccess.get_directories_at(path).is_empty():
			continue
		return path
	return ""


## `name`'s test dir as {dir} or {error}.
static func package_test_dir_for(name:String, found:Dictionary) -> Dictionary:
	if found.ambiguous.has(name):
		return {"error": "Package name '%s' is ambiguous: %s" % [name, ", ".join(found.ambiguous[name])]}
	if not found.packages.has(name):
		return {"error": "No directory or package named: " + name}
	var dir = package_test_dir(found.packages[name])
	if dir == "":
		return {"error": "Package '%s' has no tests in %s" % [name, " or ".join(ExportIgnore.NAMES.map(func(d): return d.path_join(TEST_DIR)))]}
	return {"dir": dir}


## A target argument as {dir, recursive} or {error}. A trailing `...` means recursive. A relative path
## whose first segment isn't a dir in `cwd` names a package; `found` is a find_packages result.
static func resolve(cwd:String, arg:String, found:Dictionary) -> Dictionary:
	var recursive = arg.get_file() == "..."
	var rel = arg.trim_suffix("...")
	var dir = ""
	if rel.is_absolute_path():
		dir = rel
	elif rel == "":
		dir = cwd
	else:
		var first = rel.get_slice("/", 0)
		if DirAccess.dir_exists_absolute(cwd.path_join(first)):
			dir = cwd.path_join(rel).simplify_path()
		else:
			var pkg = package_test_dir_for(first, found)
			if pkg.has("error"):
				return pkg
			dir = pkg.dir.path_join(rel.trim_prefix(first)).simplify_path()
	if not DirAccess.dir_exists_absolute(dir):
		return {"error": "Directory not found: " + arg}
	dir = ProjectSettings.globalize_path(dir)
	if not dir.begins_with(ProjectSettings.globalize_path("res://")):
		return {"error": "Target directory not in project: " + dir}
	return {"dir": dir, "recursive": recursive}


## Coroutine. Native suites run in process; GUT / GdUnit4 ones through FrameworkRunner. Returns
## TestRunner's report shape, framework suites tagged with `framework`.
static func run_files(files:Array) -> Dictionary:
	var classifier = TestFrameworks.new()
	classifier.index_classes(files)
	classifier.index_global_classes()
	var split = classifier.split(files)
	var report = await TestRunner.run_files(split["native"])
	for kind in ["gut", "gdunit4"]:
		var part = await FrameworkRunner.run(kind, split[kind])
		for suite in part.suites:
			suite.framework = kind
		report.suites.append_array(part.suites)
		report.failed += part.failed
	return report


## The .gd files in `dir` (all levels when recursive); run_files skips non-suites.
static func collect(dir:String, recursive:bool) -> Array:
	if recursive:
		return Array(GetFiles.scan(dir, ["gd"]))
	var files = []
	for n in DirAccess.get_files_at(dir):
		if n.get_extension() == "gd":
			files.append(dir.path_join(n))
	return files


## Every package's test files, recursively.
static func all_files(found:Dictionary) -> Array:
	var files = []
	for nm in found.packages:
		var dir = package_test_dir(found.packages[nm])
		if dir != "":
			files.append_array(GetFiles.scan(dir, ["gd"]))
	return files


static func _walk(dir:String, out:Array) -> void:
	for sub in DirAccess.get_directories_at(dir):
		if sub.begins_with(".") or ExportIgnore.is_name(sub):
			continue
		var path = dir.path_join(sub)
		out.append(path)
		_walk(path, out)

