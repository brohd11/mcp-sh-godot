
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

const Context = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/context.gd")
const Execute = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/execute.gd")
const Load = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/load.gd")
# Ships the builtins in exports; Load reaches them by an untagged path.
const _BuiltinScripts = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/builtin_scripts.gd")
const Types = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/types.gd")

## Empty until a request ends, so the first request starts from the root ctx's own defaults.
var cwd:String = ""
var cwn:String = ""

var _options:Dictionary
var _builtin_scopes = null
var _added_scopes:Dictionary = {}
var _undo_session = null
signal _turn_freed
var _running := false
var _queue:Array[int] = []
var _next_ticket := 0


#! keys builtins:bool host_data:Dictionary command_dirs:Array commands:Dictionary
## builtins (default true): offer GDSh's builtins. host_data: hooks for every request's ctx
## (see docs/commands.md). command_dirs and commands ({name: path}): added as by add_command_dir
## and add_command.
func _init(options:Dictionary = {}) -> void:
	_options = options
	for dir in options.get("command_dirs", []):
		add_command_dir(str(dir))
	var commands = options.get("commands", {})
	for name in commands:
		add_command(str(commands[name]), str(name))


## Add a directory of commands (as GDSh.Load.load_directory). They replace the host's own
## commands of the same name.
func add_command_dir(dir:String) -> bool:
	if not DirAccess.dir_exists_absolute(dir):
		push_warning("GDSh.Host: command dir not found: " + dir)
		return false
	_added_scopes.merge(Load.load_directory(dir), true)
	return true


## Add one command script, under `name` or its own command name.
func add_command(path:String, name:String = "") -> bool:
	var script = Load.load_command(path)
	if script == null:
		return false
	if name.is_empty():
		name = script.get_command_name()
	_added_scopes[name] = {Types.ScopeDataKeys.SCRIPT: script}
	return true


## Every command offered, by name: {name: scope data}. Names starting with "__" are internal.
func get_scopes() -> Dictionary:
	var scopes:Dictionary = _get_scopes().duplicate()
	scopes.merge(_added_scopes, true)
	for name in scopes.keys():
		if str(name).begins_with("__"):
			scopes.erase(name)
	return scopes


## The offered commands, sorted: [{name, summary}].
func host_commands() -> Array:
	var commands = []
	var scopes = get_scopes()
	var names = scopes.keys()
	names.sort()
	for name in names:
		var command = _instance(scopes[name])
		if command == null:
			continue
		var help = command.get_help_string()
		commands.append({
			"name": name,
			"summary": help.get_slice("\n", 0) if help is String else "",
		})
	return commands


## Full help for an offered command, with every subcommand under it. Empty for an unknown
## name. Awaitable: it runs `name --help` in turn with other requests.
func host_help(name:String) -> String:
	var command = _instance(get_scopes().get(name))
	if command == null:
		return ""
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


## Run one offered command once its turn comes, waiting for async commands to finish.
## argv[0] is the command name; `stdin` is what it reads as piped input. Output is plain text
## (no BBCode). Returns {stdout, stderr, exit_code}.
func host_run(argv:Array, stdin:String = "") -> Dictionary:
	if argv.is_empty() or _instance(get_scopes().get(str(argv[0]))) == null:
		var shown = str(argv[0]) if not argv.is_empty() else ""
		return {"stdout": "", "stderr": "Unknown command: %s\n" % shown, "exit_code": Types.ExitCode.ERR}
	var work = func():
		var root = _create_root_ctx()
		if not cwd.is_empty(): root.cwd = cwd
		if not cwn.is_empty(): root.cwn = cwn
		var ctx = Context.new_ctx("Host request", root)
		ctx.scopes.merge(_added_scopes, true)
		ctx.stdin = stdin
		await Execute.execute_argv(argv, ctx)
		# `cd` and `cn` propagate up to the root.
		cwd = root.cwd
		cwn = root.cwn
		return {
			"stdout": Context.plain_text(ctx.stdout),
			"stderr": Context.plain_text(ctx.stderr),
			"exit_code": ctx.exit_code,
		}
	return await _run_serialized(work)


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

