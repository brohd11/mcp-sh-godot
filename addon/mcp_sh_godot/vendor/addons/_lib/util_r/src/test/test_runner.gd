
## Runs `*_test.gd` suites. A suite exposes an entry func (run / run_test / run_tests, static or not)
## returning {result: failure count, output: Array}; a `success` bool is still accepted. Shared by
## the editor console's `test` and gdpackage's test CI, so both judge a suite the same way.

const GetFiles = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/util_r/src/file/get_files.gd") #! resolve UtilR.Files.GetFiles

const ENTRY_FUNCS = ["run", "run_test", "run_tests"]
const SUFFIX = "_test.gd"


## Suite files under `dir`, sorted so runs and reports are stable.
static func find_suites(dir:String, recursive:bool = true) -> Array:
	var paths = []
	if recursive:
		var search = GetFiles.open(dir)
		search.file_extensions = ["gd"]
		paths = Array(search.get_files())
	elif DirAccess.dir_exists_absolute(dir):
		for n in DirAccess.get_files_at(dir):
			paths.append(dir.path_join(n))
	paths = paths.filter(func(p:String): return p.ends_with(SUFFIX))
	paths.sort()
	return paths


## Coroutine (suites may await frames). Files that aren't suites are skipped. Returns
## {suites: [{path, passed, output}], failed: int, invalid: [paths with no entry func]}.
## A suite that doesn't load, or returns no Dictionary, fails rather than stopping the run.
static func run_files(paths:Array) -> Dictionary:
	var report = {"suites": [], "failed": 0, "invalid": []}
	for path:String in paths:
		if not path.ends_with(SUFFIX):
			continue
		var script = load(path)
		if not script is Script:
			_add(report, path, false, ["could not load " + path])
			continue
		var entry = entry_func(script)
		if entry.is_empty():
			report.invalid.append(path)
			continue
		var target = script if entry.is_static else script.new()
		var res = await target.call(entry.name)
		if not res is Dictionary:
			_add(report, path, false, ["%s() returned %s, not a Dictionary" % [entry.name, type_string(typeof(res))]])
			continue
		_add(report, path, passed(res), Array(res.get("output", [])))
	return report


## {name, is_static} of the script's entry func, or {}.
static func entry_func(script:Script) -> Dictionary:
	for m in script.get_script_method_list():
		if m.name in ENTRY_FUNCS:
			return {"name": m.name, "is_static": bool(m.flags & METHOD_FLAG_STATIC)}
	return {}


static func passed(res:Dictionary) -> bool:
	var value = res.get("success") if res.has("success") else res.get("result", false)
	if value is bool:
		return value
	if value is int:
		return value == 0
	return false


static func _add(report:Dictionary, path:String, ok:bool, output:Array) -> void:
	report.suites.append({"path": path, "passed": ok, "output": output})
	if not ok:
		report.failed += 1


