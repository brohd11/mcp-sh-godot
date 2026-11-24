
extends RefCounted
## A GDSh session for an outside caller, such as the mcp-sh-godot bridge. It lists commands,
## gives their help, and runs one command at a time from an argument list. Outside syntax
## (pipes, quoting, variables) belongs to the caller and never reaches GDSh.
##
## Callers use only the host_* methods and add_command*, so they work with any GDSh copy,
## including one bundled into an exported plugin without its class_name. A console shares its
## commands, context and queue by extending this and overriding the virtuals.
##
## The working directory (cwd) and working node (cwn) carry over between requests: `cd` and
## `cn` in one request set them for the next.
##
##   var host = GDSh.Host.new({"command_dirs": ["res://game/commands"]})
##   var result = await host.host_run(["ls", "res://"])   # {stdout, stderr, exit_code}

const Context = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/context.gd")
const Execute = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/execute.gd")
const Load = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/load.gd")
# Ships the builtins in exports; Load reaches them by an untagged path.
const _BuiltinScripts = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtin_scripts.gd")
const Types = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/types.gd")

## Empty until a request ends, so the first request starts from the root ctx's own defaults.
var cwd:String = ""
var cwn:String = ""

var _options:Dictionary
var _builtin_scopes = null
## Added dirs and commands, in the order added (later ones win): {dir, scopes} or {name, script}.
var _added:Array[Dictionary] = []
## User command files that failed to load, under the name each would have: {name: {path, error}}.
## Refreshed with the user directories, so they are offered and say why when run.
var _broken:Dictionary = {}
var _undo_session = null
## The running request's cancel token (see cancel()).
var _running_token = null
signal _turn_freed
var _running := false
var _queue:Array[int] = []
var _next_ticket := 0


#! keys builtins:bool host_data:Dictionary default_dirs:bool command_dirs:Array commands:Dictionary
## builtins (default true): offer GDSh's builtins. host_data: hooks for every request's ctx
## (see docs/commands.md). default_dirs: add_default_dirs() first. command_dirs and commands
## ({name: path}): added as by add_command_dir and add_command.
func _init(options:Dictionary = {}) -> void:
	_options = options
	if options.get("default_dirs", false):
		add_default_dirs()
	for dir in options.get("command_dirs", []):
		add_command_dir(str(dir))
	var commands = options.get("commands", {})
	for name in commands:
		add_command(str(commands[name]), str(name))


## Add a directory of commands (as GDSh.Load.load_directory). They replace the host's own
## commands of the same name. A user directory (GDSh.Load.is_user_path) is listed again on
## every request, so commands added to it later show up without a restart.
func add_command_dir(dir:String) -> bool:
	if not DirAccess.dir_exists_absolute(dir):
		push_warning("GDSh.Host: command dir not found: " + dir)
		return false
	_added.append({"dir": dir, "scopes": Load.load_directory(dir)})
	return true


## Add a command package: its <path>/cmd/ dir (as GDSh.Load.load_package).
func add_package(path:String) -> bool:
	return add_command_dir(path.path_join("cmd"))


## Add the ~/.gdsh and res://.gdsh commands and packages (GDSh.Load.default_dirs). Listed again
## on every request, so a package cloned there later shows up without a restart.
func add_default_dirs() -> void:
	_added.append({"defaults": true})


## Add a command root's commands/ and packages/<name>/cmd dirs (GDSh.Load.root_dirs). Listed
## again on every request, so the root may not exist yet.
func add_command_root(root:String) -> void:
	_added.append({"root": root})


## Add one command script, under `name` or its own command name.
func add_command(path:String, name:String = "") -> bool:
	var script = Load.load_command(path)
	if script == null:
		return false
	if name.is_empty():
		name = script.get_command_name()
	_added.append({"name": name, "script": script})
	return true


## The added commands by name, user directories listed fresh (which also refreshes _broken).
func _get_added_scopes() -> Dictionary:
	var scopes = {}
	var broken = {}
	for entry in _added:
		if entry.has("name"):
			scopes[entry.name] = {Types.ScopeDataKeys.SCRIPT: entry.script}
		elif entry.has("defaults"):
			for dir in Load.default_dirs():
				_merge_user_dir(dir, scopes, broken)
		elif entry.has("root"):
			for dir in Load.root_dirs(entry.root):
				_merge_user_dir(dir, scopes, broken)
		elif Load.is_user_path(entry.dir):
			_merge_user_dir(entry.dir, scopes, broken)
		else:
			scopes.merge(entry.scopes, true)
	for name in scopes:
		broken.erase(name)
	_broken = broken
	return scopes


## A user dir listed fresh into scopes, with its failed files into broken.
static func _merge_user_dir(dir:String, scopes:Dictionary, broken:Dictionary) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	scopes.merge(Load.load_directory(dir), true)
	var errors = Load.user_build_errors(dir)
	for path in errors:
		var name = _command_file_name(dir, path)
		if not name.is_empty():
			broken[name] = {"path": path, "error": errors[path]}


## The command a file in dir would be (dir/name.gd or dir/name/name.gd), or "" for others.
static func _command_file_name(dir:String, path:String) -> String:
	var rel = path.trim_prefix(dir.trim_suffix("/") + "/")
	var parts = rel.split("/")
	if parts.size() == 1 and rel.ends_with(".gd") and rel != "manifest.gd":
		return rel.get_basename()
	if parts.size() == 2 and parts[1] == parts[0] + ".gd":
		return parts[0]
	return ""


func _broken_result(name:String) -> Dictionary:
	var info = _broken[name]
	var text = "%s: %s failed to load:\n%s\n" % [name, info.path, info.error]
	return {"stdout": "", "stderr": text, "exit_code": Types.ExitCode.ERR}


## Failed user files under a user command's folder (its subcommands), as notes for stderr.
static func _broken_notes(scope) -> String:
	var script = scope.get(Types.ScopeDataKeys.SCRIPT) if scope is Dictionary else null
	if not script is GDScript or script.resource_path.is_empty() or not Load.is_user_path(script.resource_path):
		return ""
	var notes = ""
	var errors = Load.user_build_errors(script.resource_path.get_base_dir())
	for path in errors:
		notes += "note: %s failed to load:\n%s\n" % [path, errors[path]]
	return notes


## Every command offered, by name: {name: scope data}. Names starting with "__" are internal.
func get_scopes() -> Dictionary:
	var scopes:Dictionary = _get_scopes().duplicate()
	scopes.merge(_get_added_scopes(), true)
	for name in scopes.keys():
		if str(name).begins_with("__"):
			scopes.erase(name)
	return scopes


## The offered commands, sorted: [{name, summary}].
func host_commands() -> Array:
	var commands = []
	var scopes = get_scopes()
	for name in scopes:
		var command = _instance(scopes[name])
		if command == null:
			continue
		var help = command.get_help_string()
		commands.append({
			"name": name,
			"summary": help.get_slice("\n", 0) if help is String else "",
		})
	for name in _broken:
		commands.append({"name": name, "summary": "failed to load: run it to see why"})
	commands.sort_custom(func(a, b): return str(a.name) < str(b.name))
	return commands


## Full help for an offered command, with every subcommand under it. Empty for an unknown
## name. Awaitable: it runs `name --help` in turn with other requests.
func host_help(name:String) -> String:
	var command = _instance(get_scopes().get(name))
	if command == null:
		return _broken_result(name).stderr.strip_edges() if _broken.has(name) else ""
	var result = await host_run([name, "--help"])
	var text = str(result.get("stdout", "")).strip_edges()
	var tree = {}
	_get_scope_commands(command, "", tree, name)
	tree.erase(name)
	if not tree.is_empty():
		text += "\n\nAll commands under %s:" % name
		for path in tree:
			text += "\n  %s: %s" % [path, tree[path]]
	return text


#! keys timeout_ms:int max_output:int cancel_check:Callable
## Run one offered command once its turn comes, waiting for async commands to finish.
## argv[0] is the command name; `stdin` is what it reads as piped input. Output is plain text
## (no BBCode). Returns {stdout, stderr, exit_code}.
## opts, all optional and off by default: timeout_ms counts from this call, so time spent queued
## counts too; max_output caps output bytes; cancel_check is polled at checkpoints and returns a
## reason to stop ("" to go on). Hitting any of them cancels the run (exit 124 or 130).
func host_run(argv:Array, stdin:String = "", opts:Dictionary = {}) -> Dictionary:
	var timeout_ms = int(opts.get("timeout_ms", 0))
	var deadline = Time.get_ticks_msec() + timeout_ms if timeout_ms > 0 else 0
	var scopes = get_scopes()
	if not argv.is_empty() and _broken.has(str(argv[0])):
		return _broken_result(str(argv[0]))
	if argv.is_empty() or _instance(scopes.get(str(argv[0]))) == null:
		var shown = str(argv[0]) if not argv.is_empty() else ""
		return {"stdout": "", "stderr": "Unknown command: %s\n" % shown, "exit_code": Types.ExitCode.ERR}
	var work = func():
		var root = _create_root_ctx()
		if not cwd.is_empty(): root.cwd = cwd
		if not cwn.is_empty(): root.cwn = cwn
		var ctx = Context.new_ctx("Host request", root)
		var token = ctx.cancel_token
		token.deadline_ms = deadline
		token.max_output = int(opts.get("max_output", 0))
		var check = opts.get("cancel_check")
		if check is Callable:
			token.check = check
		ctx.scopes.merge(_get_added_scopes(), true)
		ctx.stdin = stdin
		_running_token = token
		await Execute.execute_argv(argv, ctx)
		_running_token = null
		# `cd` and `cn` propagate up to the root.
		cwd = root.cwd
		cwn = root.cwn
		var stderr = Context.plain_text(ctx.stderr)
		# A broken subcommand otherwise reads as an unknown one.
		if ctx.exit_code != Types.ExitCode.OK:
			var notes = _broken_notes(ctx.scopes.get(str(argv[0])))
			if not notes.is_empty():
				stderr += ("" if stderr.is_empty() or stderr.ends_with("\n") else "\n") + notes
		return {
			"stdout": Context.plain_text(ctx.stdout),
			"stderr": stderr,
			"exit_code": ctx.exit_code,
		}
	return await _run_serialized(work)


## Cancel the request that is running, if any; it stops at its next check.
func cancel(reason:String = "cancelled") -> void:
	if _running_token != null:
		_running_token.cancel(reason)


#region Virtuals

## The host's own commands, by name. Default: GDSh's builtins, unless options.builtins is false.
func _get_scopes() -> Dictionary:
	if _builtin_scopes == null:
		_builtin_scopes = Load.load_builtins() if _options.get("builtins", true) else {}
	return _builtin_scopes


## A root ctx for one request. Default: a fresh ctx with the host's commands and host_data,
## sharing one undo session across requests.
func _create_root_ctx():
	var root = Context.new("Host", false)
	root.scopes_hidden = _get_scopes().duplicate()
	root.host_data.merge(_options.get("host_data", {}), true)
	if _undo_session == null:
		_undo_session = root.host_data.get("undo_session")
	root.host_data["undo_session"] = _undo_session
	return root


## Run `work` (a Callable returning the result) after earlier requests finish. Default: this
## host's own queue. A console overrides it to take turns with its input.
func _run_serialized(work:Callable):
	var ticket = _next_ticket
	_next_ticket += 1
	_queue.append(ticket)
	while _running or _queue.front() != ticket:
		await _turn_freed
	_queue.pop_front()
	_running = true
	var result = await work.call()
	_running = false
	# Deferred: the finished caller gets its result before the next turn starts.
	_turn_freed.emit.call_deferred()
	return result

#endregion


## A command object for scope data, or null. Duck-typed, so commands built on another GDSh
## copy still count.
static func _instance(data):
	if not data is Dictionary:
		return null
	var command = data.get(Types.ScopeDataKeys.SCRIPT)
	if command is GDScript:
		command = Load.fresh(command).new()
	if command is Object and command.has_method("execute") and command.has_method("get_help_string"):
		return command
	return null


## Every subcommand path under a command, with its one-line summary.
static func _get_scope_commands(scope, current_path:String, list:Dictionary, registered_name:String = ""):
	var path = current_path + " " + (registered_name if not registered_name.is_empty() else scope.get_command_name())
	path = path.strip_edges()
	var help = scope.get_help_string()
	if help == null or help == "":
		help = "Undocumented or namespace"
	elif help.contains("\n"):
		help = help.get_slice("\n", 0)
	list[path] = help

	var subs = scope.get_commands()
	for s in subs.keys():
		var get_cmd = subs[s].get(&"get_command")
		if get_cmd != null:
			_get_scope_commands(get_cmd.call(), path, list)

