extends RefCounted
## Runs GUT / GdUnit4 suites through each framework's own CLI in a headless Godot (one process per
## framework, files passed explicitly) and reads per-suite results back from its JUnit XML. Out of
## process: neither framework has a stable in-process runner, and a crash can't take the editor down.



const GUT = "gut"
const GDUNIT4 = "gdunit4"
const SCRIPTS = {
	GUT: "res://addons/gut/gut_cmdln.gd",
	GDUNIT4: "res://addons/gdUnit4/bin/GdUnitCmdTool.gd",
}
const NAMES = {GUT: "GUT", GDUNIT4: "GdUnit4"}
## Exit codes that still mean every test passed (GdUnit4's RETURN_WARNING: orphans and the like).
const PASSING_EXITS = {GUT: [0], GDUNIT4: [0, 101]}
const TMP_ROOT = "user://gdsh_test"
const OUTPUT_TAIL = 30


## Coroutine. TestRunner.run_files' report shape: {suites: [{path, passed, output}], failed, invalid}.
static func run(kind:String, files:Array) -> Dictionary:
	var report = {"suites": [], "failed": 0, "invalid": []}
	files = files.filter(declares_tests) # shared test bases aren't suites of their own
	if files.is_empty():
		return report
	var script:String = SCRIPTS[kind]
	if not FileAccess.file_exists(script):
		for path in files:
			_add(report, path, false, ["%s is not installed (%s not found)" % [NAMES[kind], script]])
		return report
	var tmp = ProjectSettings.globalize_path(TMP_ROOT).path_join("%s_%d" % [kind, Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(tmp)
	var args = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", script]
	args.append_array(cli_args(kind, files.map(ProjectSettings.localize_path), tmp))
	var proc = await _execute(OS.get_executable_path(), args)
	var suites = parse_junit(_read_xml(tmp))
	_remove_dir(tmp)
	merge(report, kind, files, suites, proc.exit, proc.output)
	return report


## Both frameworks run `test*` methods; a file without one is a base or helper.
static func declares_tests(path:String) -> bool:
	var tests = RegEx.create_from_string(r"(?m)^func[\t ]+test")
	return tests.search(FileAccess.get_file_as_string(path)) != null


static func cli_args(kind:String, res_files:Array, tmp:String) -> Array:
	if kind == GUT:
		# -gconfig= keeps .gutconfig.json dirs from adding tests nobody targeted.
		return ["-gconfig=", "-gtest=" + ",".join(res_files), "-gexit", "-gjunit_xml_file=" + tmp.path_join("gut.xml")]
	var args = []
	for path in res_files:
		args.append_array(["-a", path])
	# -c: run everything, not stop at the first failing suite.
	args.append_array(["-c", "--ignoreHeadlessMode", "-rd", tmp, "-rc", "1"])
	return args


## JUnit XML texts -> [{key, passed, output}], key being the suite's path relative to res://.
## GUT names a suite by that path; GdUnit4 by file basename, with the dir in `package`.
static func parse_junit(texts:Array) -> Array:
	var suites = []
	for text:String in texts:
		var xml = XMLParser.new()
		if xml.open_buffer(text.to_utf8_buffer()) != OK:
			continue
		var suite = {}
		var case_name = ""
		var capturing = false
		while xml.read() == OK:
			match xml.get_node_type():
				XMLParser.NODE_ELEMENT:
					match xml.get_node_name():
						"testsuite":
							var name = xml.get_named_attribute_value_safe("name")
							if not name.ends_with(".gd"):
								name = xml.get_named_attribute_value_safe("package").path_join(name + ".gd")
							suite = {"key": name.trim_prefix("res://"), "passed": true, "output": []}
						"testcase":
							case_name = xml.get_named_attribute_value_safe("name")
						"failure", "error":
							if not suite.is_empty():
								suite.passed = false
								suite.output.append("FAIL %s: %s" % [case_name, xml.get_named_attribute_value_safe("message")])
								capturing = not xml.is_empty()
				XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
					if capturing:
						# XMLParser keeps CDATA content in the node name.
						var data = xml.get_node_data() if xml.get_node_type() == XMLParser.NODE_TEXT else xml.get_node_name()
						for line in data.split("\n", false):
							if not line.strip_edges().is_empty():
								suite.output.append("\t" + line.strip_edges())
				XMLParser.NODE_ELEMENT_END:
					match xml.get_node_name():
						"failure", "error":
							capturing = false
						"testsuite":
							if not suite.is_empty():
								suites.append(suite)
							suite = {}
	return suites


## One report entry per file, from its JUnit suite. A file the report lacks takes the exit code's
## verdict; a failing exit with no failing suite (crash, script errors) adds a "<GUT run>" entry.
static func merge(report:Dictionary, kind:String, files:Array, suites:Array, exit:int, output:String) -> void:
	var exit_ok = exit in PASSING_EXITS[kind]
	var by_key = {}
	for suite in suites:
		by_key[suite.key] = suite
	var any_failed = false
	for path:String in files:
		var key = ProjectSettings.localize_path(path).trim_prefix("res://")
		if by_key.has(key):
			_add(report, path, by_key[key].passed, by_key[key].output)
			any_failed = any_failed or not by_key[key].passed
		else:
			var lines = ["no result in the %s report (exit code %d)" % [NAMES[kind], exit]]
			if not exit_ok:
				lines.append_array(_tail(output))
			_add(report, path, exit_ok, lines)
			any_failed = any_failed or not exit_ok
	if not exit_ok and not any_failed:
		_add(report, "<%s run>" % NAMES[kind], false, ["exit code %d" % exit] + _tail(output))


## {exit, output}, OS.execute on a thread so the editor keeps drawing while the suites run.
static func _execute(exe:String, args:Array) -> Dictionary:
	var result = {"exit": -1, "output": ""}
	var thread = Thread.new()
	thread.start(func():
		var out = []
		result.exit = OS.execute(exe, PackedStringArray(args), out, true)
		result.output = "".join(out))
	var tree = Engine.get_main_loop() as SceneTree
	while tree != null and thread.is_alive():
		await tree.process_frame
	thread.wait_to_finish()
	return result


static func _read_xml(dir:String) -> Array:
	var texts = []
	for sub in [dir, dir.path_join("report_1")]:
		if not DirAccess.dir_exists_absolute(sub):
			continue
		for name in DirAccess.get_files_at(sub):
			if name.get_extension() == "xml":
				texts.append(FileAccess.get_file_as_string(sub.path_join(name)))
	return texts


static func _tail(output:String) -> Array:
	var ansi = RegEx.create_from_string("\u001b\\[[0-9;]*m")
	var lines = Array(ansi.sub(output, "", true).split("\n", false)).filter(func(l): return not l.strip_edges().is_empty())
	return lines.slice(-OUTPUT_TAIL).map(func(l): return "\t" + l)


static func _remove_dir(dir:String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_remove_dir(dir.path_join(sub))
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)


static func _add(report:Dictionary, path:String, ok:bool, output:Array) -> void:
	report.suites.append({"path": path, "passed": ok, "output": output})
	if not ok:
		report.failed += 1

