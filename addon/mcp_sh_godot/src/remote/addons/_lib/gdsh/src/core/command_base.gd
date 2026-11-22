
extends RefCounted

const Types = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/types.gd")
const Context = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/context.gd")
const Completion = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/completion.gd")
const Options = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/options.gd")
const Paths = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/paths.gd")
const PathCompletion = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/path_completion.gd")
const Utils = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/utils.gd")
const ErrorCapture = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/util_r/src/object/error_capture.gd")
const PRINT_DEBUG = false
const _UNAMED = "UnamedCommand"

const ExitCode = Types.ExitCode
const FlagType = Types.FlagType

static var _positional_arg_count_regex:RegEx

var _ctx_obj:Context

var consumed_tokens:Array[String] = []
var positional_args:Array[String] = []
var positional_arg_index = -1

var payload:Array = []
var payload_index = -1

func _initialize(ctx:Context):
	positional_args = []
	consumed_tokens = []
	payload = []
	positional_arg_index = -1
	payload_index = -1
	_ctx_obj = ctx

static func get_command_name() -> String:
	return _UNAMED

func __get_name__():
	var nm = get_command_name()
	if nm == _UNAMED:
		_ctx_obj.append_output("Unamed Command in -> " + get_script().resource_path.get_file())
	return nm

static func get_self_command_data() -> Dictionary:
	return {_UNAMED: true}

#! keys i-Options.add_option;
static func _command_data(params:={}):
	return Options.process_option_dict(params)

func __get_self_command_data__() -> Dictionary:
	var params = get_self_command_data()
	if params.has(_UNAMED):
		_ctx_obj.append_output("Command doesn't have self_option_data defined -> " + get_script().resource_path.get_file())
		#print("Command doesn't have self_option_data defined -> ", get_script().resource_path.get_file())
		return {}
	if params.has(&"option_name"):
		return params
	var name = get_command_name()
	var processed = Options.get_single_option_dict(name, params)
	return processed

func get_help_string(full_string:bool=false) -> String:
	var help = get_self_command_data().get(&"help", "")
	if not full_string or help == "":
		return help

	var flags = get_flags()
	flags.erase(Options.Keys.COMMAND_META)
	if flags.size() > 0:
		help += "\nFlags:"
		# "-r, --recursive" labels; long-only flags are indented to line up once any flag has a short form
		var has_shorts = not _short_flag_map().is_empty()
		var labels = {}
		var flag_width = 0
		for f in flags.keys():
			if Options.Keys.get_seperator(f) != null:
				continue
			var short = flags[f].get(&"short", "")
			labels[f] = ("-%s, " % short if short != "" else "    " if has_shorts else "") + f
			flag_width = maxi(flag_width, labels[f].length())
		for f in flags.keys():
			var separator = Options.Keys.get_seperator(f)
			if separator != null:
				# label already carries its own decorators (see Options.add_separator)
				help += "\n  " + separator if separator != "" else "\n"
				continue
			var f_help = flags[f].get(&"help", "")
			if f_help == "":
				help += "\n  " + labels[f]
				continue
			if f_help.contains("\n"):
				f_help = f_help.get_slice("\n", 0)
			help += "\n  " + labels[f].rpad(flag_width) + "  " + f_help

	var commands = get_commands()
	commands.erase(Options.Keys.COMMAND_META)
	if commands.size() > 0:
		help += "\nSubcommands:"
		for c in commands.keys():
			help += "\n  " + c
	return help


func _route(ctx:Context, completion:Completion=null):
	_initialize(ctx)
	var result = _consume_self(ctx)
	if result != ExitCode.OK: return result
	var in_payload = false
	while not ctx.unconsumed_tokens.is_empty():
		var token:String = ctx.unconsumed_tokens[0]
		var meta = ctx._token_metadata.front() if not ctx._token_metadata.is_empty() else {}
		var literal = meta.get("literal", false)
		if not in_payload and not literal:
			if token == "--help" or token == "-h":
				if ctx.execute: ctx.append_output(get_help_string(true))
				return ExitCode.OK
			if token == "--":
				_consume_token(ctx)
				in_payload = true
				continue
			if _is_short_group(token):
				# Commands without short flags keep dash words as arguments ([ -f x ], -5).
				var shorts = _short_flag_map()
				if not shorts.is_empty():
					var unknown = ""
					for letter in token.substr(1):
						if not shorts.has(letter):
							unknown = letter
							break
					if unknown != "":
						if completion != null and ctx.unconsumed_tokens.size() == 1: break
						ctx.append_error("Unrecognized flag: -" + unknown)
						return ExitCode.ERR
					_consume_token(ctx)
					for letter in token.substr(1):
						consumed_tokens.append(shorts[letter]) # Completion hides flags already given.
						if _process_flag(shorts[letter]) == ExitCode.ERR:
							return ExitCode.ERR
					continue
			if token.begins_with("--"):
				var flag = _split_flag(token)
				if not get_flags().has(flag):
					if completion != null and ctx.unconsumed_tokens.size() == 1: break
					ctx.append_error("Unrecognized flag: " + flag)
					return ExitCode.ERR
				if _process_flag(_consume_token(ctx)) == ExitCode.ERR:
					return ExitCode.ERR
				continue
			if positional_args.is_empty():
				var commands = get_commands()
				var data = _resolve_subcommand(token, commands)
				if data != null:
					return data.get_command.call() if data.has("get_command") else _get_command(token)
		var value = _consume_token(ctx)
		if in_payload: payload.append(value)
		else: positional_args.append(value)
	if completion != null:
		var next = completion.char_before_cursor in [" ", "\t", "\n", ""]
		if in_payload:
			payload_index = payload.size() if next else maxi(0, payload.size() - 1)
			positional_arg_index = -1
		else:
			positional_arg_index = positional_args.size() if next else maxi(0, positional_args.size() - 1)
	return null

## A dash followed only by letters, such as -ir. Digits and a lone dash stay arguments.
static func _is_short_group(token:String) -> bool:
	if token.length() < 2 or token[0] != "-":
		return false
	for letter in token.substr(1):
		if not (letter >= "a" and letter <= "z" or letter >= "A" and letter <= "Z"):
			return false
	return true

## Letter -> long flag name, for flags that declare &"short".
func _short_flag_map() -> Dictionary:
	var shorts = {}
	var flags = get_flags()
	for f in flags:
		if flags[f] is Dictionary and flags[f].has(&"short"):
			shorts[flags[f][&"short"]] = f
	return shorts

func _consume_self(ctx:Context) -> ExitCode:
	_consume_token(ctx)
	return ExitCode.OK

func _consume_token(ctx:Context):
	var tok = ctx.unconsumed_tokens.pop_front()
	if not ctx._token_metadata.is_empty(): ctx._token_metadata.pop_front()
	consumed_tokens.append(tok)
	return tok

func execute(ctx:Context):
	# Raw commands only parse at command position; routed tokens would lose their source.
	if has_method("execute_raw") and get_self_command_data().get(&"raw", false):
		ctx.append_error("%s takes raw arguments; call it by name at command position" % get_command_name())
		ctx.exit_code = ExitCode.ERR
		return ExitCode.ERR
	var selected = _route(ctx)
	if PRINT_DEBUG:
		print("CommandBase execute - selected::", selected)
	if selected is ExitCode:
		ctx.exit_code = selected
		return selected
	if selected:
		return await selected.execute(ctx)
	# no child selected: this node requires one -> print usage
	if not _correct_positional_count():
		_get_help_for_token(consumed_tokens.front())
		return ExitCode.FAIL

	var result = await await_exit_code(ctx, get_command_name(), _execute.bind(ctx))
	ctx.exit_code = result
	return result

## Await a command's run (it may be a coroutine) and return its exit code. Commands must return
## an ExitCode: null means a script error aborted it, so report what Godot logged meanwhile.
static func await_exit_code(ctx:Context, name:String, run:Callable) -> int:
	var sink = ErrorCapture.start()
	@warning_ignore("redundant_await")
	var result = await run.call()
	var errors = ErrorCapture.stop(sink)
	if result is int:
		return result
	for e in errors:
		ctx.append_error(e)
	if errors.is_empty():
		ctx.append_error("%s: no exit code returned (a script error, or a missing return)" % name)
	return ExitCode.ERR

## Must return an ExitCode; see await_exit_code.
func _execute(ctx:Context):
	var help = consumed_tokens.front()
	_get_help_for_token(help)
	return ExitCode.FAIL

func complete(completion:Completion):
	var selected = _route(completion.context, completion)
	if selected is ExitCode:
		return {} # selected # completions recieve a dictionary, should not be an issue I think
	elif is_instance_valid(selected):
		return selected.complete(completion)

	completion.positional_args = positional_args.duplicate()
	completion.positional_arg_index = positional_arg_index
	completion.payload_args = payload.duplicate()
	completion.payload_arg_index = payload_index
	return _get_completions(completion)

func _get_completions(completion:Completion):
	if not _positional_arg_index_valid():
		return {}

	var current_flag_completions = _get_flag_type_completions(completion)
	if current_flag_completions != null:
		return current_flag_completions

	return _get_completion_std_w_context(completion)

func _get_completion_std_w_context(completion:Completion, commands:=true, flags:=true) -> Dictionary:
	var command_data = get_self_command_data()
	var allow_pos_paths = command_data.get(&"allow_positional_paths", false)

	var options = Options.new()
	var _do_com:=false
	var _do_flag:=false
	var _do_path:=false
	var path = positional_args.back() if not positional_args.is_empty() else ""
	if completion.char_before_cursor == "" or completion.char_before_cursor == " ":
		_do_flag = true
		_do_com = true
	elif completion.token_before_cursor.begins_with("--"):
		_do_flag = true
	else:
		_do_com = true
		_do_flag = true
		for s in ["/", "../", "./"]:
			if path.begins_with(s):
				_do_path = true
				break

	if allow_pos_paths and _do_path:
		options.merge(PathCompletion.files(path, completion.context.cwd, completion.token_before_cursor))
	else:
		if _do_com and commands:
			options.merge(get_commands(true))
		if _do_flag and flags:
			options.merge(get_flags(true))

	return options.get_options()

## checks if the first unconsumed or the last consumed begins with --
func _completion_last_is_flag(completion:Completion):
	if completion.context.unconsumed_tokens.size() == 1 and completion.context.unconsumed_tokens.front().begins_with("--"):
		return true
	if consumed_tokens.size() > 0 and consumed_tokens.back().begins_with("--"):
		return true
	return false

func get_flags(hide_consumed:=false) -> Dictionary:
	var options = _get_flags()
	if not hide_consumed:
		return options
	#for c in options.keys():
		#var split = _split_flag(c)
		#if split in consumed_tokens:
			#options.erase(c)
	for c in consumed_tokens:
		var split = _split_flag(c)
		if options.has(split):
			options.erase(split)
	return options


func _get_flags() -> Dictionary:
	return {}

func _split_flag(token:String):
	if not token.contains("="):
		return token
	return token.substr(0, token.find("=") + 1)

func _get_flag_value(token:String):
	if not token.contains("="):
		return ""
	var val = token.substr(token.find("=") + 1)
	return val

#! keys i-Options.add_option;
func _get_option_data(token:String, flags:Dictionary, commands:Dictionary):
	if token == __get_name__():
		return __get_self_command_data__()
	var data = flags.get(token)
	if data == null:
		data = commands.get(token)
	return data

func _process_flag(flag:String):
	return _flag_set_var(flag)

## Sets the var named after the flag: "--dry-run" -> dry_run_flag = true, "--count=3" ->
## count_flag = 3, converted to the var's current type (an untyped null var takes the string).
## Returns ExitCode.ERR when the var is missing or the value doesn't convert.
func _flag_set_var(flag:String):
	if not flag.begins_with("--"):
		return
	var var_name = _split_flag(flag).trim_prefix("--").trim_suffix("=").replace("-", "_") + "_flag"
	if not var_name in self:
		_ctx_obj.append_error("gdsh command - _flag_set_var - could not find var: %s" % var_name)
		return ExitCode.ERR

	if not flag.contains("="):
		set(var_name, true)
		return
	var val = _get_flag_value(flag)
	var target_type = typeof(get(var_name))
	if target_type == TYPE_NIL:
		set(var_name, val)
		return
	var converted = Utils_Value.convert(val, target_type)
	if converted == null:
		_ctx_obj.append_error("Invalid value for %s%s (expected %s)" % [_split_flag(flag), val, type_string(target_type)])
		return ExitCode.ERR
	set(var_name, converted)

func get_commands(hide_consumed:=false) -> Dictionary:
	var options = _get_commands()
	if not hide_consumed:
		return options
	for c in options.keys():
		if c in consumed_tokens:
			options.erase(c)
	return options

func _get_commands() -> Dictionary:
	return _get_commands_in_dir()

## Loose or not, a command owns the name/name.gd dirs beside it, so each namespace gets its own folder.
## An in-memory command has no path; "" would list the process cwd.
func _get_commands_in_dir(sort_priority:=true):
	var path = get_script().resource_path
	if path.is_empty():
		return {}
	var loader = Utils.get_loader()
	var scopes = loader.load_directory(path.get_base_dir(), true)
	var options = {}
	for scope in scopes.values():
		Options.add_command_script_to_dict(scope[Types.ScopeDataKeys.SCRIPT], options)
	if sort_priority:
		options = Utils.sort_dict_with_priority_key(options, &"priority")
	return options


## Routing hook shared by execution and completion. Overrides may recognize alternate
## spellings while leaving the original token for the selected child's _consume_self.
func _resolve_subcommand(token:String, commands:Dictionary):
	return commands.get(token)


func _get_command(command:String):
	_ctx_obj.append_error("Unrecognized command - get command: " + command)
	return

func _get_help_for_token(token:String):
	var split = _split_flag(token)
	var option_data = _get_option_data(split, get_flags(), get_commands())
	if option_data != null and option_data.has(&"help"):
		_ctx_obj.append_output(get_help_string(true))
	else:
		_get_help(token)


func _get_help(what:String):
	_ctx_obj.append_error("Unrecognized command - help base: " + what)

func _correct_positional_count(target_size:int=-1):
	if target_size == -1:
		target_size = _get_target_positional_count()
	if positional_args.size() != target_size:
		_ctx_obj.append_error("Err: " + get_command_name())
		_ctx_obj.append_error("Positional argument count incorrect: Expected %s, got %s" % [target_size, positional_args.size()])
		_ctx_obj.append_error("Arguments: " + str(positional_args))
		_ctx_obj.exit_code = ExitCode.FAIL
		return false
	return true

func _get_target_positional_count() -> int:
	var count = get_self_command_data().get(&"positional_count", 0)
	if count is int:
		return count
	if count is String:
		_initialize_regex()
		var reg_match = _positional_arg_count_regex.search(count)
		if is_instance_valid(reg_match):
			var min_count = reg_match.get_string("min")
			var max_count = reg_match.get_string("max")
			if min_count == "":
				min_count = 0
			else:
				min_count = min_count.to_int()
			if max_count == "":
				max_count = positional_args.size()
			else:
				max_count = max_count.to_int()
			var arg_size = positional_args.size()
			if arg_size >= min_count and arg_size <= max_count:
				return arg_size
			elif arg_size < min_count:
				return min_count
			elif arg_size > max_count:
				return max_count


	return 0

func _positional_arg_index_valid():
	var target_pos_count = _get_target_positional_count()
	if target_pos_count == 0 and positional_arg_index < 1:
		return true  # if 0, allow 1, this will let completion of 1 unconsumed token through
	return target_pos_count > positional_arg_index

func _add_variables_to_completions(dict:Dictionary):
	Options.add_show_variables_to_dict(dict)

func _get_flag_type_completions(completion:Completion):
	if not (completion.token_before_cursor.contains("=") and completion.char_before_cursor != " "):
		return null

	var all_options = get_flags(false)
	var flag_name = _split_flag(completion.token_before_cursor)
	var flag_data = all_options.get(flag_name)
	if flag_data == null or not flag_data.has(&"flag_completion"):
		return null
	var flag_type_data = flag_data.get(&"flag_completion", {"type": FlagType.NONE})
	var flag_type:FlagType = flag_type_data.get("type", FlagType.NONE)
	if flag_type == FlagType.NONE:
		return {}
	var target_dir = flag_type_data.get("dir", "res://")
	var completions = []
	if flag_type == FlagType.FILE:

		var extensions = flag_type_data.get("ext", [])
		var files = Paths.walk(target_dir)
		if extensions.is_empty() and target_dir == "res://":
			completions = files
		else:
			for f in files:
				if (extensions.is_empty() or f.get_extension() in extensions) and f.begins_with(target_dir):
					completions.append(f)


	elif flag_type == FlagType.DIR:
		var dirs = Paths.walk(target_dir, true)
		if target_dir == "res://":
			completions = dirs
		else:
			for d in dirs:
				if d.begins_with(target_dir):
					completions.append(d)

	elif flag_type == FlagType.CLASS:
		var classes = ClassDB.get_class_list()
		completions.append_array(classes)
		var user_classes = Utils.get_all_global_class_paths().keys()
		completions.append_array(user_classes)

	elif flag_type == FlagType.USER_CLASS:
		var user_classes = Utils.get_all_global_class_paths().keys()
		completions.append_array(user_classes)


	var flag_options = Options.new()
	for c in completions:
		flag_options.add_option(c, {

		})
	return flag_options.get_options()


static func _completion_rel_path(ctx:Context, current_rel_path:String):
	var target_dir = ctx.cwd
	# Keep the user's prefix for insertion; only resolve it for directory lookup.
	var insert_base = current_rel_path.left(current_rel_path.rfind("/") + 1)
	var options = Options.new()
	if current_rel_path != "":
		target_dir = _complete_path(current_rel_path, ctx.cwd)
		if target_dir.ends_with("/"):
			pass
		elif target_dir.contains("/"):
			target_dir = target_dir.get_base_dir()

		if not DirAccess.dir_exists_absolute(target_dir):
			return {}

	var dirs = DirAccess.get_directories_at(target_dir)
	dirs = Array(dirs)
	dirs.push_front("..")
	for dir in dirs:
		options.add_option(dir, {
			&"insert": insert_base + dir,
			&"trailing_char": "/"
		})

	return options.get_options()


func print_available_commands():
	var commands = get_commands()
	commands.erase(Options.Keys.COMMAND_META)
	if commands.size() > 0:
		_ctx_obj.append_output("Available commands:")
		for c in commands:
			_ctx_obj.append_output("\t" + c)

func complete_path(to_check:String):
	return _complete_path(to_check, _ctx_obj.cwd)

## Relative paths will be completed via base_dir, absolute are returned unchanged
static func _complete_path(to_check:String, base_dir:String):
	if to_check.is_absolute_path():
		return to_check
	var simp = base_dir.path_join(to_check).simplify_path()
	simp += "/" if to_check.ends_with("/") else "" # simplify path strips the trailing slash
	return simp


static func _initialize_regex():
	if not is_instance_valid(_positional_arg_count_regex):
		_positional_arg_count_regex = RegEx.new()
		_positional_arg_count_regex.compile(r"(?=min:|max:)(?:min:\s*(?<min>[0-9]+))?(?:\s*,?\s*)?(?:max:\s*(?<max>[0-9]+))?")



### GDPackage Global Classes
const Utils_Value = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/value.gd")

