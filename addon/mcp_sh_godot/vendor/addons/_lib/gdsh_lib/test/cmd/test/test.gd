extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"

const TestTargets = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/test/src/test_targets.gd")

const _HELP = \
"Run the *_test.gd suites in a directory. '...' indicates recursive. A relative path whose first
segment isn't a dir in the cwd names a package, resolved to its _export_ignore/test/ (or export_ignore/test/).
GUT and GdUnit4 suites found there run through their own CLI in a headless Godot.
Usage: test [--verbose] [--report-invalid] [--all] [optional: package[/subdir][/...]]"

var verbose_flag := false
var report_invalid_test_flag := false
var all_flag := false

static func get_command_name():
	return "test"

static func get_self_command_data():
	return _command_data({
		&"discoverable": false,
		&"help": _HELP,
		&"positional_count": "max: 1",
		&"allow_positional_paths": true,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--verbose", {
		&"help": "Print the full test report, not just PASS/FAIL."
	})
	options.add_option("--report-invalid", {
		&"help": "Report tests that have *_test.gd name, but don't have any test entry funcs."
	})
	options.add_option("--all", {
		&"help": "Run every package's tests, recursively."
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--verbose":
		verbose_flag = true
	elif flag == "--report-invalid":
		report_invalid_test_flag = true
	elif flag == "--all":
		all_flag = true

## TestTargets.find_packages() result. Editor Console overrides this with its cached scan.
func _packages() -> Dictionary:
	return TestTargets.find_packages()

func _execute(ctx:Context):
	if all_flag:
		if positional_args.size() > 0:
			ctx.append_error("--all takes no target: " + positional_args[0])
			return ExitCode.ERR
		return await _run_files(ctx, TestTargets.all_files(_packages()), "any package")

	var target = TestTargets.resolve(ctx.cwd, positional_args[0] if positional_args.size() > 0 else "", _packages())
	if target.has("error"):
		ctx.append_error(target.error)
		return ExitCode.ERR
	return await _run_files(ctx, TestTargets.collect(target.dir, target.recursive), target.dir)


func _run_files(ctx:Context, files:Array, label:String) -> int:
	var report = await TestTargets.run_files(files)
	for suite in report.suites:
		var tag = " (%s)" % suite.framework if suite.has("framework") else ""
		ctx.append_output("Test: [%s] : %s%s" % ["PASS" if suite.passed else "FAIL", suite.path, tag])
		if verbose_flag:
			for line in suite.output:
				ctx.append_output("\t" + str(line))
	if report_invalid_test_flag:
		for path in report.invalid:
			ctx.append_error("Could not run tests in: %s" % path)

	if report.suites.is_empty():
		ctx.append_output("No tests found in: " + label)
	if report_invalid_test_flag and not report.invalid.is_empty():
		return ExitCode.ERR
	if report.failed > 0:
		return ExitCode.FAIL
	return ExitCode.OK

