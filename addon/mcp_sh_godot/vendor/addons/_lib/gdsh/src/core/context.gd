
extends RefCounted

const Context = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/context.gd")
const Types = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/types.gd")
const Undo = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/undo.gd")
const Utils = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/utils.gd")
const NodePaths = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/node_paths.gd")
const Cancel = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/cancel.gd")
const FileSystem = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/filesystem.gd")
const _Anchor = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/anchor.gd")
const ExitCode = Types.ExitCode
static var _clean_output_regex:RegEx

enum Propagate{
	VARIABLES,
	FUNCTIONS,
	ALIASES,
	PROPERTY,
}

var title:String


var execute:bool = true
var unconsumed_tokens:= []
# Parallel source metadata keeps quoted flag-like arguments literal.
var _token_metadata:Array = []
var _function_cache:Dictionary = {}
var data := {}
## Optional host integration. Hooks must not execute commands during completion.
var scope_resolver:Callable
var raw_commands:Array[String] = []
## Host services/bindings, separate from per-command control-flow data.
var host_data:Dictionary = {}

var parent_ctx:Context

var positional_args := []
var variables := {}
var functions := {}
var aliases := {}
var scopes := {}
## Commands that resolve normally but are omitted from root completion.
var scopes_hidden := {}

var cwd:String = "res://"
## Current working node, as an absolute node path: the base for relative node paths, as cwd is
## for relative file paths. Held as a path and resolved on use, so a freed node cannot dangle.
var cwn:String = "/root"

var stdin:String
var stdout:String
var stderr:String

## Live output channel: `Callable(text:String, is_error:bool)`, installed by a host on its
## submission context and inherited by children through `new_ctx`. The sink runs inside the
## running command's call stack: it must not await, execute commands, or touch this context.
var output_sink:Callable
## Sinks saved by a program that takes over the output view (push_output_sink/pop_output_sink).
var _sink_stack:Array = []
## Frames capturing a stream as data: a redirect route, a non-final pipe stage, `$(...)` stdout.
## Output is still buffered, but not streamed, while the matching counter is above zero.
var _capture_out:int = 0
var _capture_err:int = 0

var last_status:int = ExitCode.OK
var exit_code:int = ExitCode.OK
var exit_requested:=false
## Shared by every ctx of a run (see cancel.gd). A session (made with Context.new) isn't a run:
## each child of it starts a new one, so a cancelled submission never sticks to the console.
var cancel_token:Cancel = Cancel.new()
var _in_run := false


var raw_text:String


func _init(text:="", include_builtins:=true) -> void:
	title = text if not text.is_empty() else "GDSh Context"
	raw_text = text
	# Child contexts share their parent's session through the shallow host_data copy.
	host_data["undo_session"] = Undo.Session.new()
	if include_builtins:
		scopes_hidden = Utils.get_loader().load_builtins()


## Load a command file or directory into this Context. New registrations replace
## the same name in either visibility dictionary.
func load(path:String, hidden:=false) -> Dictionary:
	var resolved = path
	if not path.is_absolute_path():
		resolved = cwd.path_join(path).simplify_path()
	var loader = Utils.get_loader()
	var loaded := {}
	if resolved.get_extension().to_lower() == "gd":
		var script = loader.load_command(resolved)
		if script != null:
			for name in [script.get_command_name()] + Array(script.get_command_aliases()):
				loaded[name] = {Types.ScopeDataKeys.SCRIPT: script}
	else:
		loaded = loader.load_directory(resolved)
	var target = scopes_hidden if hidden else scopes
	var other = scopes if hidden else scopes_hidden
	for name in loaded:
		other.erase(name)
		target[name] = loaded[name]
	return loaded


## Load a command package's <path>/cmd/ dir (see GDSh.Load.load_package).
func load_package(path:String, hidden:=false) -> Dictionary:
	var resolved = path if path.is_absolute_path() else cwd.path_join(path).simplify_path()
	if not DirAccess.dir_exists_absolute(resolved.path_join("cmd")):
		push_error("GDSh.Context: package has no cmd/ dir: " + resolved)
		return {}
	return self.load(resolved.path_join("cmd"), hidden)


## A bound provider never falls back to physical files, including when it fails.
func has_filesystem() -> bool:
	return FileSystem.bound(self)


func resolve_path(path:String) -> Dictionary:
	return FileSystem.resolve(self, path)


func stat_path(path:String) -> Dictionary:
	return FileSystem.operation(self, "stat", path)


func list_directory(path:String) -> Dictionary:
	return FileSystem.operation(self, "list_dir", path)


func read_file(path:String) -> Dictionary:
	return FileSystem.operation(self, "read_text", path)


func walk_directory(path:String) -> Dictionary:
	return FileSystem.walk(self, path)


func has_scope(name:String) -> bool:
	return get_scope(name) != null


func get_scope(name:String):
	var registered = get_registered_scope(name)
	if registered != null:
		return registered
	return _resolve_bare(name)


## Scopes a host actually registered, without bare target resolution. Syntax highlighting uses
## this so a global class, node path or script path is not coloured as though someone had
## registered a command by that name.
func get_registered_scope(name:String):
	if scopes.has(name):
		return scopes[name]
	if scopes_hidden.has(name):
		return scopes_hidden[name]
	if scope_resolver.is_valid():
		return scope_resolver.call(name, self)
	return null


## A bare target in command position: a .gdsh script, a .gd script, a global class, or a node.
## Returns the scope of the command that handles it, so core owns the policy while the commands
## stay replaceable and an unregistered one simply does not resolve.
## Runs for every unrecognized name, every completion keystroke and every highlighted word, so it
## must stay cheap and side-effect free.
func _resolve_bare(name:String):
	if name.is_empty():
		return null
	match name.get_extension().to_lower():
		"gdsh": return _bare_scope("gdsh")
		"gd": return _bare_scope("script")
	var target_util = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/target_util.gd")
	if target_util.parse_script_target(name).is_file:
		return _bare_scope("script")
	# A class name never contains a slash, so a slashed token is a path, not a class.
	if name.contains("/"):
		return _bare_scope("node") if _bare_node(name) != null else null
	# The head before the first '.' decides: neither node names nor class names contain one.
	var head = name.get_slice(".", 0)
	var is_class = Utils.global_class_paths().has(head)
	var is_node = _bare_node(head) != null
	if is_class and is_node:
		return _bare_scope("__ambiguous__")
	if is_class:
		return _bare_scope("script")
	if is_node:
		return _bare_scope("node")
	return null


## Look the handler up directly rather than through get_scope, which would recurse.
func _bare_scope(command_name:String):
	if scopes.has(command_name):
		return scopes[command_name]
	return scopes_hidden.get(command_name)


func _bare_node(path:String) -> Node:
	return NodePaths.resolve(path, cwn)


## Set raw_commands to the registered names whose command data declares `raw`.
## Reads static command data only; no command is instantiated.
func collect_raw_commands() -> void:
	var names:Array[String] = []
	for registry in [scopes_hidden, scopes]:
		for name in registry:
			var command = registry[name].get(Types.ScopeDataKeys.SCRIPT)
			if command == null or not (command is GDScript or command.has_method("get_self_command_data")):
				continue
			if command.get_self_command_data().get(&"raw", false) and not name in names:
				names.append(name)
	raw_commands = names

func set_positional_args(path_or_name:String, args:Array):
	variables["$0"] = path_or_name
	positional_args = args

func execute_parse():
	var tokenizer = load(_Anchor.path("src/core/tokenizer.gd")).new(self)
	tokenizer.execute = true
	var token_data = tokenizer.parse_command_string_execute(raw_text)
	unconsumed_tokens = token_data.expanded
	_token_metadata = token_data.metadata
	if not token_data.error.is_empty():
		load(_Anchor.path("src/core/execute.gd"))._parse_error(self, token_data.error)
	execute = true

func tokens_empty_and_execute() -> bool:
	return unconsumed_tokens.is_empty() and execute

func tokens_empty() -> bool:
	return unconsumed_tokens.is_empty()

## A line of command output: one trailing newline, empty text ignored. Also streams the
## appended text when a sink is installed and this stream is not being captured as data.
func append_output(line:String) -> void:
	_write(line, false, true)

## Output appended exactly as given, preserving blank lines and partial lines.
func write_output(text:String) -> void:
	_write(text, false, false)

## A child's buffer, appended without streaming: the child already streamed its own output,
## so emitting again here would show it twice.
func absorb_output(text:String) -> void:
	_write(text, false, true, false)

func strip_output_newlines():
	stdout = stdout.lstrip("\n").rstrip("\n")
	return stdout

func clean_output():
	return plain_text(stdout)

func clean_text(text:String):
	return plain_text(text)

## Text with BBCode color markup removed, as output becomes data (pipes, $(...), files).
## Text without color tags is returned unchanged; `[lb]` escapes from Utils.color_text are restored.
static func plain_text(text:String) -> String:
	if not text.contains("[color="):
		return text
	if not is_instance_valid(_clean_output_regex):
		_clean_output_regex = RegEx.new()
		_clean_output_regex.compile("\\[color=[^\\[\\]]*\\]|\\[/color\\]")
	return _clean_output_regex.sub(text, "", true).replace("[lb]", "[")


## Stop this run (every ctx sharing its token) at the next check, e.g. from a console's Ctrl+C.
func cancel(reason:String = "cancelled") -> void:
	cancel_token.cancel(reason)


func is_cancelled() -> bool:
	return cancel_token.is_cancelled()


## For long loops: `if await ctx.checkpoint(): return ExitCode.CANCELLED`. Yields a frame now
## and then, so check that nodes are still valid after it.
func checkpoint() -> bool:
	return await cancel_token.checkpoint()


func append_error(line:String) -> void:
	_write(line, true, true)

## Errors appended exactly as given, preserving blank lines and partial lines.
func write_error(text:String) -> void:
	_write(text, true, false)

## A child's error buffer, appended without streaming. See absorb_output.
func absorb_error(text:String) -> void:
	_write(text, true, true, false)


## The single funnel for every buffer write. `normalize` applies the append_* convention
## (exactly one trailing newline, empty text dropped); `emit` streams the appended text.
## The streamed chunk is byte-identical to what lands in the buffer.
func _write(text:String, is_error:bool, normalize:bool, emit:=true) -> void:
	if text.is_empty():
		return
	var chunk = text
	if normalize:
		chunk = text.trim_suffix("\n") + "\n"
	# Counted once, where it is first written; absorbing a child's buffer doesn't count again.
	if emit and not is_error and not cancel_token.add_output(chunk.length()):
		return
	if is_error:
		stderr += chunk
	else:
		stdout += chunk
	if emit and should_stream(is_error):
		output_sink.call(chunk, is_error)


## Stream text the caller appends to a buffer itself, so it is not emitted twice
## (see Execute._run, which builds redirection write errors as a local string).
func emit_error_text(text:String) -> void:
	if not text.is_empty() and should_stream(true):
		output_sink.call(text, true)


## Whether output written now reaches the host's live channel: a sink is installed and this
## stream is not being captured as data by an enclosing frame.
func should_stream(is_error:=false) -> bool:
	if not output_sink.is_valid():
		return false
	if is_error:
		return _capture_err == 0
	return _capture_out == 0


## Mark a stream as captured for the duration of an enclosing frame. Every begin_capture
## needs a matching end_capture on all paths, or streaming stays off for the rest of the run.
func begin_capture(out:bool, err:bool) -> void:
	if out: _capture_out += 1
	if err: _capture_err += 1


func end_capture(out:bool, err:bool) -> void:
	if out: _capture_out = maxi(0, _capture_out - 1)
	if err: _capture_err = maxi(0, _capture_err - 1)


func set_output_sink(callback:Callable) -> void:
	output_sink = callback


func clear_output_sink() -> void:
	output_sink = Callable()


## Take over the live channel, keeping the previous sink to restore later.
func push_output_sink(callback:Callable) -> void:
	_sink_stack.append(output_sink)
	output_sink = callback


func pop_output_sink() -> void:
	output_sink = _sink_stack.pop_back() if not _sink_stack.is_empty() else Callable()

func strip_error_newlines():
	stderr = stderr.lstrip("\n").rstrip("\n")
	return stderr

## The host's undo object from `host_data["undo_redo"]: Callable() -> Object`, or null to
## apply changes directly.
func get_undo_redo() -> Object:
	var hook = host_data.get("undo_redo")
	return hook.call() if hook is Callable and hook.is_valid() else null

## The compound undo buffer shared by this context and its children.
func get_undo_session() -> Undo.Session:
	return host_data.get("undo_session")

## One undoable action per command; buffered instead while a compound is open.
func undo_action(name:String) -> Undo.Action:
	return Undo.Action.new(name, get_undo_redo(), get_undo_session())

func get_variable(name:String):
	return load(_Anchor.path("src/core/tokenizer.gd")).check_variable(name, self)

func get_root_ctx():
	var inherited = get_inherited_ctxs()
	if inherited.is_empty():
		return self
	return inherited.back()

func get_inherited_ctxs():
	var inherited = []
	if not is_instance_valid(parent_ctx):
		return inherited
	var parent:Context = parent_ctx
	while is_instance_valid(parent):
		inherited.append(parent)
		parent = parent.parent_ctx

	return inherited


static func new_ctx(text:String, parent:Context=null, sub_shell:=false):
	var ctx = load(_Anchor.path("src/core/context.gd")).new(text, not is_instance_valid(parent))
	if is_instance_valid(parent):
		if not sub_shell: # so that function definitions do not populate up
			ctx.parent_ctx = parent

		ctx.scope_resolver = parent.scope_resolver
		ctx.raw_commands = parent.raw_commands # Host configuration, shared rather than copied.
		ctx.host_data = parent.host_data.duplicate()
		ctx.cwd = parent.cwd
		ctx.cwn = parent.cwn
		ctx.execute = parent.execute

		# The live channel and any capture in progress: a child created inside a pipe stage,
		# a redirect, or `$(...)` inherits the suppression that applies to its parent.
		ctx.output_sink = parent.output_sink
		if parent._in_run:
			ctx.cancel_token = parent.cancel_token
		ctx._in_run = true
		ctx._capture_out = parent._capture_out
		ctx._capture_err = parent._capture_err


		ctx.variables = parent.variables.duplicate()
		ctx.functions = parent.functions.duplicate()
		ctx.aliases = parent.aliases.duplicate()
		ctx.scopes = parent.scopes.duplicate()
		ctx.scopes_hidden = parent.scopes_hidden.duplicate()

		 # non piped inherit stdin, this will be overwritten if piped
		ctx.stdin = parent.stdin
		ctx.last_status = parent.last_status
		ctx.positional_args = parent.positional_args.duplicate()

	return ctx

func write_to_parent(parent:Context):
	parent.absorb_output(stdout.trim_suffix("\n"))
	parent.absorb_error(stderr.trim_suffix("\n"))
	exit_code = last_status
	parent.last_status = exit_code

func propogate(target:Propagate, key:String, value):
	var inher = get_inherited_ctxs()
	inher.append(self)
	match target:
		Propagate.VARIABLES:
			for inh:Context in inher:
				inh.variables[key] = value
		Propagate.FUNCTIONS:
			for inh:Context in inher:
				inh.functions[key] = value
		Propagate.ALIASES:
			for inh:Context in inher:
				inh.aliases[key] = value
		Propagate.PROPERTY:
			for inh:Context in inher:
				inh.set(key, value)

