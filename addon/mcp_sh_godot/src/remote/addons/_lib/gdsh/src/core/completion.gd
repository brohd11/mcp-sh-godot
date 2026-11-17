
extends RefCounted
## A UI-independent completion request. Routing operates on an isolated context.

const Context = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/context.gd")
const Parser = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/parser.gd")
const Expansion = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/expansion.gd")
const Options = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/options.gd")
const Types = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/types.gd")
const Utils = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/utils.gd")
const NodePaths = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/node_paths.gd")
const PathCompletion = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/path_completion.gd")
const TargetUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/target_util.gd")

var raw_text:String
var caret_col:int
var char_before_cursor:String
var word_before_cursor:String
var token_before_cursor:String
var positional_args:Array = []
var positional_arg_index:int = -1
var payload_args:Array = []
var payload_arg_index:int = -1
var context:Context
var show_commands:bool = true
var show_flags:bool = true

var _session:Context
var _current_command:String
var raw_arguments:String
var raw_argument_start:int = -1
var _redirect:bool = false
var _redirect_op:String = ""
var _redirect_word:Dictionary = {}

func _init(text:String, session:Context, caret:int=-1):
	raw_text = text
	_session = session
	caret_col = text.length() if caret < 0 else clampi(caret, 0, text.length())

func get_completions() -> Dictionary:
	_parse()
	if _redirect:
		return _redirect_completions()
	var options = Options.new()
	if raw_argument_start < 0 and token_before_cursor.begins_with("@") and not char_before_cursor in [" ", "\t"]:
		for name in context.aliases:
			var source = str(context.aliases[name]).trim_prefix("@literal").strip_edges()
			options.add_option("%s = [%s]" % [name, source], {&"insert": name})
		return options.get_options()
	if raw_argument_start < 0 and token_before_cursor.begins_with("$") and not token_before_cursor.begins_with("$(") and not char_before_cursor in [" ", "\t"]:
		for name in context.variables:
			options.add_option(name)
		return options.get_options()

	var first_word = context.unconsumed_tokens.front() if not context.unconsumed_tokens.is_empty() else ""
	var scope = context.get_scope(first_word)
	var typing_command = raw_argument_start < 0 and context.unconsumed_tokens.size() == 1 and not char_before_cursor in [" ", "\t", "\n", ""] and not context.functions.has(first_word)
	if typing_command and (first_word.begins_with("./") or first_word.begins_with("../")):
		# Relative filesystem paths and node paths overlap. Keep script member access
		# and registered commands with their own completion handlers.
		if not TargetUtil.parse_script_target(first_word).has_members and context.get_registered_scope(first_word) == null:
			return _relative_path_completions(first_word) if show_commands else {}
	if scope == null:
		if show_commands:
			for name:String in context.scopes:
				if not name.begins_with("__") and Utils.is_discoverable(context.scopes[name]):
					options.add_option(name)
			for name in context.functions:
				options.add_option(name + "[func]", {&"insert": name})
			# Bare node completion starts after a named parent and slash, never at
			# an initial node name. Incomplete children need not resolve yet.
			if typing_command and first_word.rfind("/") > 0 and context._bare_scope("node") != null:
				options.merge(NodePaths.complete_path(first_word, context.cwn, token_before_cursor))
		return options.get_options()
	if context.functions.has(first_word):
		return {}
	var command = scope.get(Types.ScopeDataKeys.SCRIPT)
	if command is GDScript:
		command = Utils.get_loader().fresh(command).new()
	if not is_instance_valid(command) or not command.has_method("complete"):
		return {}
	var result
	if raw_argument_start >= 0:
		result = command.complete_raw(raw_arguments, self) if command.has_method("complete_raw") else {}
	else:
		result = command.complete(self)
	if result == null:
		return {}
	if result is Object and result.has_method("get_options"):
		result = result.get_options()
	if not result is Dictionary:
		push_error("GDSh.Completion: expected an options dictionary")
		return {}
	options.set_options(result)
	var meta = result.get(Options.Keys.COMMAND_META, {})
	if payload_arg_index > -1:
		options.remove_option("--")
		if meta.get(Options.Keys.SHOW_VARIABLES, false) and not context.variables.is_empty():
			options.add_separator("Variables")
			for name in context.variables:
				options.add_option(name)
	var output = options.get_options()
	for name in output.keys():
		if name == Options.Keys.COMMAND_META:
			continue
		if output[name].has(&"get_command"):
			if not show_commands:
				output.erase(name)
		elif not show_flags:
			output.erase(name)
	return output


func _relative_path_completions(path:String) -> Dictionary:
	var options = Options.new()
	options.set_options(PathCompletion.files(path, context.cwd, token_before_cursor))
	if context._bare_scope("node") != null:
		var nodes = NodePaths.complete_path(path, context.cwn, token_before_cursor)
		nodes.erase(Options.Keys.COMMAND_META)
		if not nodes.is_empty():
			options.add_separator("Nodes")
			var choices = options.get_options()
			for name in nodes:
				# A directory and a node may share a name. Keep both groups intact.
				var label = name
				if choices.has(label):
					label = str(name) + " [node]"
					while choices.has(label):
						label += " [node]"
				choices[label] = nodes[name]
	return options.get_options()


func _parse():
	context = Context.new("", false)
	if _session != null:
		context.scope_resolver = _session.scope_resolver
		context.raw_commands = _session.raw_commands
		context.host_data = _session.host_data.duplicate()
		context.cwd = _session.cwd
		context.cwn = _session.cwn
		context.variables = _session.variables.duplicate(true)
		context.aliases = _session.aliases.duplicate(true)
		context.functions = _session.functions.duplicate(true)
		context.scopes = _session.scopes.duplicate(true)
		context.scopes_hidden = _session.scopes_hidden.duplicate(true)
		context.data = _session.data.duplicate(true)
		context.positional_args = _session.positional_args.duplicate(true)
		context.stdin = _session.stdin
		context.last_status = _session.last_status
	context.execute = false
	positional_args = []
	positional_arg_index = -1
	payload_args = []
	payload_arg_index = -1
	var prefix = raw_text.left(clampi(caret_col, 0, raw_text.length()))
	var parsed = Parser.parse(prefix, true, context.raw_commands)
	var current = parsed.completion
	_current_command = prefix.substr(current.start).strip_edges(true, false)
	context.raw_text = _current_command
	char_before_cursor = prefix.right(1)
	_redirect = current.redirect
	_redirect_op = current.get("redirect_op", "")
	_redirect_word = current.get("redirect_word", {})
	raw_arguments = current.get("raw_args", "")
	raw_argument_start = current.get("raw_start", -1)
	var words:Array = current.words
	token_before_cursor = words.back().raw if not words.is_empty() else ""
	word_before_cursor = token_before_cursor
	# Alias definitions remain source fragments, but routing never executes them.
	var seen = {}
	while true:
		var changed = false
		var fragments:Array = []
		for word in words:
			if not word.quoted and context.aliases.has(word.raw) and not seen.has(word.raw):
				seen[word.raw] = true
				fragments.append(str(context.aliases[word.raw]).trim_prefix("@literal"))
				changed = true
			else:
				fragments.append(word.raw)
		if not changed: break
		var alias_text = " ".join(fragments)
		if raw_argument_start >= 0: alias_text += " " + raw_arguments
		var alias_completion = Parser.parse(alias_text, true, context.raw_commands).completion
		words = alias_completion.words
		raw_arguments = alias_completion.get("raw_args", "")
		raw_argument_start = alias_completion.get("raw_start", -1)
	var expanded = Expansion.words(words, context, true)
	context.unconsumed_tokens = expanded.values
	context._token_metadata = expanded.metadata

	if raw_argument_start >= 0:
		token_before_cursor = raw_arguments.get_slice(" ", raw_arguments.get_slice_count(" ") - 1)
		word_before_cursor = token_before_cursor

func _redirect_completions() -> Dictionary:
	var options = Options.new()
	options.add_option("discard")
	options.add_option("/dev/null")
	var target = ""
	if not _redirect_word.is_empty():
		target = Expansion.scalar([_redirect_word], context, true)
	if target in ["discard", "/dev/null"]:
		return options.get_options()
	var target_dir = context.cwd
	var insert_base = ""
	var leaf = ""
	if target.ends_with("/"):
		target_dir = target if target.is_absolute_path() else context.cwd.path_join(target).simplify_path()
		insert_base = target
	elif target.contains("/"):
		insert_base = target.get_base_dir()
		target_dir = insert_base if insert_base.is_absolute_path() else context.cwd.path_join(insert_base).simplify_path()
		leaf = target.get_file()
	else:
		leaf = target
	if not DirAccess.dir_exists_absolute(target_dir):
		return options.get_options()
	for name in DirAccess.get_directories_at(target_dir):
		if leaf.is_empty() or name.begins_with(leaf):
			var value = name if insert_base.is_empty() else insert_base.path_join(name)
			options.add_option(value, {&"trailing_char": "/"})
	for name in DirAccess.get_files_at(target_dir):
		if leaf.is_empty() or name.begins_with(leaf):
			var value = name if insert_base.is_empty() else insert_base.path_join(name)
			options.add_option(value)
	return options.get_options()

func in_arguments() -> bool:
	return payload_arg_index > -1

func get_current_command() -> String:
	return _current_command

