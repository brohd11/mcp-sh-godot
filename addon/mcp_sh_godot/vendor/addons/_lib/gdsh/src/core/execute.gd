
extends RefCounted
## Parse complete input before executing its tree. Only selected nodes expand words.
## Commands may `await` in `_execute`: every step awaits its command, so sequencing and status
## wait for completion. Input whose commands never pause still finishes in the calling frame.

const Context = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/context.gd")
const Types = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/types.gd")
const Parser = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/parser.gd")
const Lexer = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/lexer.gd")
const Expansion = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/expansion.gd")
const Utils = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/utils.gd")
const CommandBase = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd")
const _IS_LOOP_KEY = "__is_loop__"
const _LOOP_BREAK_KEY = "__loop_break__"
const _LOOP_CONTINUE_KEY = "__loop_continue__"
const _SUBSTITUTION_PENDING_KEY = "__substitution_pending__"
const SUBSTITUTION_FAILED_KEY = "__substitution_failed__"

static func execute_command_multiline(text:String, ctx:Context=null):
	if ctx == null: ctx = Context.new()
	if ctx.exit_requested: return ctx
	_renew_cancel(ctx)
	var parsed = Parser.parse(text, false, ctx.raw_commands)
	if not parsed.error.is_empty():
		_parse_error(ctx, parsed.error)
		return ctx
	return await _execute_tree(parsed.tree, ctx)

static func execute_command(text:String, params:Dictionary={}):
	var ctx = params.get("parent_ctx")
	if ctx == null: ctx = Context.new()
	if params.get("sub_shell", false): ctx = Context.new_ctx("Subshell", ctx, true)
	return await execute_command_multiline(text, ctx)

## Run one command from an argument list, as an outside caller (a shell, an RPC) gives it:
## argv[0] is the command name. Nothing is parsed or expanded and aliases do not apply. Dash
## words are still flags, as in other shells.
static func execute_argv(argv:Array, ctx:Context=null):
	if ctx == null: ctx = Context.new()
	if ctx.exit_requested or argv.is_empty(): return ctx
	_renew_cancel(ctx)
	if ctx.is_cancelled(): # e.g. its deadline passed while it waited for its turn
		_report_cancel(ctx)
		return ctx
	var command = Context.new_ctx("", ctx)
	for arg in argv:
		command.unconsumed_tokens.append(str(arg))
		command._token_metadata.append({"raw": str(arg), "quoted": false, "literal": false})
	command.execute = true
	await _dispatch(command)
	ctx.absorb_output(command.stdout)
	ctx.absorb_error(command.stderr)
	_set_status(ctx, command.exit_code)
	_report_cancel(ctx)
	return ctx

static func source_file(file_path:String, parent_ctx:Context=null):
	if parent_ctx == null: parent_ctx = Context.new()
	if not file_path.is_absolute_path():
		file_path = parent_ctx.cwd.path_join(file_path).simplify_path()
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		parent_ctx.append_error("Cannot open GDSh script: " + file_path)
		_set_status(parent_ctx, Types.ExitCode.FAIL)
		return parent_ctx
	var text = file.get_as_text()
	if not text.strip_edges(true, false).begins_with("#!gdsh"):
		parent_ctx.append_error("Not a gdsh script: " + file_path)
		_set_status(parent_ctx, Types.ExitCode.FAIL)
		return parent_ctx
	return await execute_command_multiline(text, parent_ctx)

## Run a `$(...)` body in `ctx` within the current frame; expansion cannot wait. A body whose
## command pauses is stopped (nothing after it runs when it resumes) and false is returned.
static func run_substitution(ctx:Context, tree:Dictionary={}, text:="") -> bool:
	ctx.data[_SUBSTITUTION_PENDING_KEY] = true
	# The body's stdout is the substitution's value rather than screen output; its stderr still shows.
	ctx.begin_capture(true, false)
	# Checkpoints inside don't yield, so long synchronous commands still finish in this frame.
	ctx.cancel_token.sync_depth += 1
	_substitution_body(ctx, tree, text) # Not awaited: returns at the first pause.
	ctx.cancel_token.sync_depth -= 1
	if not ctx.data.has(_SUBSTITUTION_PENDING_KEY):
		ctx.end_capture(true, false)
		return true
	ctx.exit_requested = true
	ctx.append_error("GDSh: async commands cannot run inside $(...)")
	# The abandoned body resumes later. Leave stdout captured and capture stderr too, so nothing
	# it writes after this point reaches the live channel of an already-failed substitution.
	ctx.begin_capture(false, true)
	return false

static func _substitution_body(ctx:Context, tree:Dictionary, text:String):
	if tree.is_empty(): await execute_command_multiline(text, ctx)
	else: await _execute_tree(tree, ctx)
	ctx.data.erase(_SUBSTITUTION_PENDING_KEY)

## A `$(...)` that could not finish fails the command that used it.
static func _substitution_failed(ctx:Context) -> bool:
	if not ctx.data.has(SUBSTITUTION_FAILED_KEY): return false
	ctx.data.erase(SUBSTITUTION_FAILED_KEY)
	_set_status(ctx, Types.ExitCode.ERR)
	return true

static func _parse_error(ctx:Context, error:Dictionary):
	ctx.append_error("GDSh syntax error at %d:%d: %s" % [error.line, error.column, error.message])
	_set_status(ctx, Types.ExitCode.ERR)

static func _set_status(ctx:Context, status:int):
	ctx.last_status = status
	if not ctx.exit_requested: ctx.exit_code = status

static func _execute_tree(tree:Dictionary, ctx:Context, aliases:Dictionary={}):
	if not ctx.exit_requested:
		await _run(tree, ctx, aliases)
	_report_cancel(ctx)
	if not ctx.exit_requested:
		ctx.exit_code = ctx.last_status
	return ctx

## A session given input directly (startup commands) shouldn't stay cancelled from last time.
static func _renew_cancel(ctx:Context):
	if not ctx._in_run and ctx.cancel_token.is_spent():
		ctx.cancel_token = Context_Cancel.new()

## A cancelled run ends with its status and one "cancelled: reason" line, however deep it stopped.
static func _report_cancel(ctx:Context):
	if not ctx.is_cancelled(): return
	ctx.append_error(ctx.cancel_token.take_report())
	_set_status(ctx, ctx.cancel_token.code)

static func _stopped(ctx:Context) -> bool:
	if ctx.exit_requested or ctx.is_cancelled(): return true
	var chain = ctx.get_inherited_ctxs()
	chain.push_front(ctx)
	for parent in chain:
		if parent.data.has("__function_return__"): return true
		if parent.data.get(_LOOP_BREAK_KEY, false) or parent.data.get(_LOOP_CONTINUE_KEY, false): return true
	return false

static func _run(node:Dictionary, ctx:Context, aliases:Dictionary):
	if _stopped(ctx) or node.is_empty(): return
	# Capture output without creating a new variable scope. Nested commands inherit
	# the surrounding destination unless their own redirections route a stream.
	var previous_out = ctx.stdout
	var previous_err = ctx.stderr
	var previous_in = ctx.stdin
	ctx.stdout = ""
	ctx.stderr = ""
	var redirects = _prepare_redirections(node.get("redirs", []), ctx)
	# Expansion/open diagnostics always remain visible on the invoking stderr.
	var setup_errors = ctx.stderr
	ctx.stderr = ""
	# A routed stream becomes file data, so it must not also reach the host's live channel.
	var capture_out = redirects.ok and redirects.stdout_route >= 0
	var capture_err = redirects.ok and redirects.stderr_route >= 0
	if redirects.ok:
		if redirects.stdin_route >= 0:
			ctx.stdin = redirects.stdin
		ctx.begin_capture(capture_out, capture_err)
		await _run_inner(node, ctx, aliases)
		ctx.end_capture(capture_out, capture_err)
	else:
		_set_status(ctx, Types.ExitCode.FAIL)
	var output = ctx.stdout
	var errors = ctx.stderr
	ctx.stdin = previous_in
	var write_errors = ""
	if redirects.ok and redirects.stdout_route >= 0 and redirects.stdout_route == redirects.stderr_route:
		write_errors += _write_redirect(redirects.routes[redirects.stdout_route], output + errors)
		output = ""
		errors = ""
	elif redirects.ok:
		if redirects.stdout_route >= 0:
			write_errors += _write_redirect(redirects.routes[redirects.stdout_route], output)
			output = ""
		if redirects.stderr_route >= 0:
			write_errors += _write_redirect(redirects.routes[redirects.stderr_route], errors)
			errors = ""
	_close_redirections(redirects)
	if not write_errors.is_empty():
		_set_status(ctx, Types.ExitCode.FAIL)
	# Built as a local string rather than through append_error, so stream it explicitly. Capture
	# has already ended, so a `2>` on this node cannot hide its own write failure.
	ctx.emit_error_text(write_errors)
	ctx.stdout = previous_out + output
	ctx.stderr = previous_err + setup_errors + errors + write_errors

static func _prepare_redirections(redirs:Array, ctx:Context) -> Dictionary:
	var result = {
		"ok": true,
		"routes": [],
		"stdin_route": -1,
		"stdout_route": -1,
		"stderr_route": -1,
		"stdin": "",
	}
	for redirect in redirs:
		var values = Expansion.word_values(redirect.target, ctx)
		if _substitution_failed(ctx):
			result.ok = false
			return result
		if values.size() != 1 or str(values[0]).is_empty():
			ctx.append_error("GDSh redirection: target must expand to exactly one non-empty path")
			result.ok = false
			return result
		var target:String = str(values[0])
		var discard = target in ["discard", "/dev/null"]
		var path = target if discard or target.is_absolute_path() else ctx.cwd.path_join(target).simplify_path()
		var route = {"discard": discard, "path": path, "file": null}
		if not discard:
			var mode = FileAccess.READ if redirect.stdin else FileAccess.WRITE
			if redirect.append and FileAccess.file_exists(path):
				mode = FileAccess.READ_WRITE
			route.file = FileAccess.open(path, mode)
			if route.file == null:
				ctx.append_error("GDSh redirection: cannot open '%s' (error %s)" % [path, FileAccess.get_open_error()])
				result.ok = false
				return result
			if redirect.append:
				route.file.seek_end()
		result.routes.append(route)
		var route_index = result.routes.size() - 1
		if redirect.stdin: result.stdin_route = route_index
		if redirect.stdout: result.stdout_route = route_index
		if redirect.stderr: result.stderr_route = route_index
	if result.stdin_route >= 0:
		var input_route = result.routes[result.stdin_route]
		if not input_route.discard:
			result.stdin = input_route.file.get_as_text()
	return result

static func _write_redirect(route:Dictionary, content:String) -> String:
	if route.discard or content.is_empty(): return ""
	if route.file.store_string(Context.plain_text(content)): return ""
	return "GDSh redirection: cannot write '%s'\n" % route.path

static func _close_redirections(redirects:Dictionary):
	for route in redirects.routes:
		if route.file != null:
			route.file.close()

static func _run_inner(node:Dictionary, ctx:Context, aliases:Dictionary):
	match node.kind:
		"list":
			for item in node.items:
				if _stopped(ctx): break
				await _run(item, ctx, aliases)
		"logical":
			await _run(node.first, ctx, aliases)
			for link in node.links:
				if _stopped(ctx): break
				if (link.op == "&&" and ctx.last_status == 0) or (link.op == "||" and ctx.last_status != 0):
					await _run(link.node, ctx, aliases)
		"pipeline":
			await _pipeline(node.stages, ctx, aliases)
		"simple":
			await _simple(node, ctx, aliases)
		"assignment":
			var value = Expansion.scalar(node.words, ctx)
			if _substitution_failed(ctx): return
			if node.local:
				ctx.variables["$" + node.name] = value
			else:
				ctx.propogate(Context.Propagate.VARIABLES, "$" + node.name, value)
			_set_status(ctx, 0)
		"alias":
			ctx.propogate(Context.Propagate.ALIASES, node.name, node.source)
			_set_status(ctx, 0)
		"function":
			ctx.propogate(Context.Propagate.FUNCTIONS, node.name, node.source)
			ctx.get_root_ctx()._function_cache[node.name] = {"source": node.source, "tree": node.body}
			_set_status(ctx, 0)
		"if":
			var selected = false
			for branch in node.branches:
				if not branch.condition.is_empty(): await _run(branch.condition, ctx, aliases)
				if _stopped(ctx): return
				if branch.condition.is_empty() or ctx.last_status == 0:
					await _run(branch.body, ctx, aliases)
					selected = true
					break
			if not selected: _set_status(ctx, 0)
		"for", "while":
			await _loop(node, ctx, aliases)
		"subshell":
			var child = Context.new_ctx("Subshell", ctx, true)
			await _execute_tree(node.body, child, aliases)
			ctx.absorb_output(child.stdout)
			ctx.absorb_error(child.stderr)
			_set_status(ctx, child.exit_code)

static func _pipeline(stages:Array, ctx:Context, aliases:Dictionary):
	var input = ctx.stdin
	for i in stages.size():
		if _stopped(ctx): break
		var saved_input = ctx.stdin
		var saved_output = ctx.stdout
		ctx.stdin = input
		ctx.stdout = ""
		var last = i == stages.size() - 1
		# Only the final stage reaches the host; earlier stdout becomes the next stage's stdin.
		# stderr is never piped, so every stage keeps streaming its diagnostics live.
		ctx.begin_capture(not last, false)
		await _run(stages[i], ctx, aliases)
		ctx.end_capture(not last, false)
		# Piped output is data for the next command; only the final stage keeps display markup.
		input = ctx.stdout if last else Context.plain_text(ctx.stdout)
		ctx.stdin = saved_input
		ctx.stdout = saved_output + (input if last else "")

static func _loop(node:Dictionary, ctx:Context, aliases:Dictionary):
	var child = Context.new_ctx("Loop", ctx)
	child.data[_IS_LOOP_KEY] = true
	var collection:Array = []
	if node.kind == "for":
		for word in node.words:
			var values = Expansion.word_values(word, ctx)
			if _substitution_failed(ctx): return
			for value in values:
				if word.quoted: collection.append(value)
				else: collection.append_array(value.replace("\t", " ").replace("\n", " ").split(" ", false))
	var count = 0
	var body_status = 0
	while not _stopped(ctx):
		# Keeps long loops responsive and cancellable; a no-op unless 50 ms have passed.
		if await child.checkpoint(): break
		if node.kind == "for":
			if count >= collection.size(): break
			child.variables["$" + node.name] = collection[count]
		else:
			if count >= 100: break # Retained GDSh loop limit.
			await _run(node.condition, child, aliases)
			if _stopped(child) or child.last_status != 0: break
		count += 1
		child.data.erase(_LOOP_CONTINUE_KEY)
		await _run(node.body, child, aliases)
		body_status = child.last_status
		if child.data.get(_LOOP_BREAK_KEY, false) or ctx.exit_requested: break
		# A return in a containing function must unwind the loop too.
		if _has_return(child): break
		child.data.erase(_LOOP_CONTINUE_KEY)
	ctx.absorb_output(child.stdout)
	ctx.absorb_error(child.stderr)
	_set_status(ctx, body_status)

static func _has_return(ctx:Context) -> bool:
	var chain = ctx.get_inherited_ctxs()
	chain.push_front(ctx)
	for parent in chain:
		if parent.data.has("__function_return__"): return true
	return false

static func _simple(node:Dictionary, ctx:Context, aliases:Dictionary):
	# Alias sources are deliberately parsed as command fragments. Expanded variable
	# values and substitution results never pass through this source-level step.
	var source_words:Array = []
	var next_aliases = aliases.duplicate()
	var changed = false
	for word in node.words:
		if not word.quoted and ctx.aliases.has(word.raw):
			if aliases.has(word.raw):
				ctx.append_error("GDSh alias cycle: " + word.raw)
				_set_status(ctx, Types.ExitCode.ERR)
				return
			next_aliases[word.raw] = true
			source_words.append(str(ctx.aliases[word.raw]).trim_prefix("@literal"))
			changed = true
		else:
			source_words.append(word.raw)
	if changed:
		var alias_source = " ".join(source_words)
		if node.has("raw_args"): alias_source += " " + node.raw_args
		var parsed = Parser.parse(alias_source, false, ctx.raw_commands)
		if not parsed.error.is_empty():
			_parse_error(ctx, parsed.error)
		else:
			await _run(parsed.tree, ctx, next_aliases)
		return
	if node.has("raw_args"):
		var command = Context.new_ctx("Raw command", ctx)
		var scope = ctx.get_scope(node.words[0].raw)
		var script = _instance(scope.get(Types.ScopeDataKeys.SCRIPT) if scope != null else null)
		if is_instance_valid(script) and script.has_method("execute_raw"):
			var name = node.words[0].raw
			command.exit_code = await CommandBase.await_exit_code(command, name, script.execute_raw.bind(node.raw_args, command))
		else:
			command.append_error("Raw command has no execute_raw handler: " + node.words[0].raw)
			command.exit_code = Types.ExitCode.ERR
		ctx.absorb_output(command.stdout)
		ctx.absorb_error(command.stderr)
		_set_status(ctx, command.exit_code)
		return
	var expanded = Expansion.words(node.words, ctx)
	if _substitution_failed(ctx): return
	if expanded.values.is_empty(): return
	var command = Context.new_ctx("", ctx)
	command.unconsumed_tokens = expanded.values
	command._token_metadata = expanded.metadata
	command.execute = true
	await _dispatch(command)
	ctx.absorb_output(command.stdout)
	ctx.absorb_error(command.stderr)
	_set_status(ctx, command.exit_code)

static func _dispatch(ctx:Context):
	var name:String = ctx.unconsumed_tokens[0]
	if ctx.functions.has(name):
		name = "__function__"
	elif not ctx.has_scope(name):
		# An absolute path used to mean "run this script"; Context._resolve_bare now classifies
		# paths by extension, so a .gdsh token reaches the gdsh command through get_scope.
		if ctx.unconsumed_tokens.has("==") or ctx.unconsumed_tokens.has("!="):
			ctx.unconsumed_tokens.push_front("[")
			ctx.unconsumed_tokens.push_back("]")
			ctx._token_metadata.push_front({})
			ctx._token_metadata.push_back({})
			name = "["
	var scope = ctx.get_scope(name)
	if scope == null: scope = {}
	var script = _instance(scope.get(Types.ScopeDataKeys.SCRIPT))
	if is_instance_valid(script) and script.has_method("execute"):
		await script.execute(ctx)
	else:
		ctx.append_error("Unrecognized command: " + name)
		ctx.exit_code = Types.ExitCode.ERR

## Scope entries hold a command script or an existing command object.
static func _instance(command):
	if command is GDScript:
		return Utils.get_loader().fresh(command).new()
	return command

static func _call_function(name:String, ctx:Context, args:Array):
	var source = str(ctx.functions.get(name, ""))
	var root = ctx.get_root_ctx()
	var cached = root._function_cache.get(name, {})
	if cached.get("source") != source:
		var parsed = Parser.parse(source, false, ctx.raw_commands)
		if not parsed.error.is_empty():
			_parse_error(ctx, parsed.error)
			return
		cached = {"source": source, "tree": parsed.tree}
		root._function_cache[name] = cached
	var child = Context.new_ctx(name, ctx)
	child.data["__function__"] = true
	child.set_positional_args(name, args)
	await _execute_tree(cached.tree, child)
	if child.data.has("__function_return__"): child.exit_code = child.data["__function_return__"]
	ctx.absorb_output(child.stdout)
	ctx.absorb_error(child.stderr)
	ctx.exit_code = child.exit_code



### GDPackage Global Classes
const Context_Cancel = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/cancel.gd")

