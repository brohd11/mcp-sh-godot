extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const TargetUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/target_util.gd")

const _HELP = \
"Target a GDScript: a global class name, a res:// / user:// / absolute path, or a path relative
to the working directory. Member access walks into inner classes (Outer.Inner).
Usage:
  script <GlobalClass|path.gd> <command>
  <GlobalClass|path.gd> <command>    the same, with the target in command position
  script --path=res://file.gd        target a script by path
  script --class=MyClass             target a global class by name"

var script_access_path:String
var text_flag:=false

static func get_command_name() -> String:
	return "script"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--text", {
		&"help": "Output the target script's source code to stdout."
	})
	options.add_option("--path=", {
		&"help": "Target a script by path, optionally followed by .Inner.",
		&"trailing_char": "",
		&"flag_completion": {"type": FlagType.FILE, "ext": ["gd"]},
	})
	options.add_option("--class=", {
		&"help": "Target a global class, optionally followed by .Inner.",
		&"trailing_char": "",
		&"flag_completion": {"type": FlagType.USER_CLASS},
	})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--text":
		text_flag = true
	elif flag.begins_with("--path=") or flag.begins_with("--class="):
		_set_script_access_path(_get_flag_value(flag))

## Entered explicitly as `script <target>`, or with the target itself in command position.
func _consume_self(ctx:Context) -> ExitCode:
	var token = _consume_token(ctx)
	if token == get_command_name():
		token = ""
		if not ctx.tokens_empty():
			var next:String = ctx.unconsumed_tokens.front()
			if not next.begins_with("-") and not next in get_commands():
				token = _consume_token(ctx)
	if ctx.stdin != "":
		token = ctx.stdin.strip_edges()
	_set_script_access_path(token)
	return ExitCode.OK


func _set_script_access_path(new_path:String):
	script_access_path = new_path
	_ctx_obj.data.erase("node")
	_ctx_obj.data["script"] = TargetUtil.resolve_access_path(new_path, _ctx_obj)
	_ctx_obj.data["script_error"] = "No script target selected." if new_path.is_empty() else "Could not resolve script target: " + new_path


## Shared by the runtime script/node routers and the editor's current-script adapter.
static func get_target_commands() -> Dictionary:
	var commands = {}
	for command in [
		preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/builtins/script/args/args.gd"),
		preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/builtins/script/call/call.gd"),
		preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/builtins/script/get_path/get_path.gd"),
		preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/builtins/script/list/list.gd"),
	]:
		Options.add_command_script_to_dict(command, commands)
	return commands


func _get_commands() -> Dictionary:
	var commands = get_target_commands()
	Options.add_command_script_to_dict(preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/builtins/script/list_global/list_global.gd"), commands)
	return commands


func _get_help(what:String):
	if script_access_path != "" and script_access_path != get_command_name():
		_ctx_obj.append_output(get_self_command_data().get(&"help"))
		print_available_commands()
	else:
		_ctx_obj.append_error("Unrecognized command: " + what)

func _get_completions(ctx:Completion):
	var token = ctx.token_before_cursor
	var has_space = ctx.char_before_cursor in [" ", "\t", "\n"]
	if not has_space and (token.begins_with("--path=") or token.begins_with("--class=")):
		var value = script_access_path # Routing already expanded/unquoted the flag value.
		if TargetUtil.parse_script_target(value).has_members:
			var choices = TargetUtil.complete_access_path(value, ctx.context)
			var prefix = token.left(token.find("=") + 1)
			return _format_target_choices(choices, token.substr(prefix.length()), prefix)
	var flag_completion = _get_flag_type_completions(ctx)
	if flag_completion != null:
		return flag_completion
	if "--text" in consumed_tokens:
		return {}
	if not has_space and positional_args.is_empty() and not token.begins_with("-") and not script_access_path.is_empty():
		var parsed = TargetUtil.parse_script_target(script_access_path)
		if parsed.has_members:
			return _format_target_choices(TargetUtil.complete_access_path(script_access_path, ctx.context), token)
		if parsed.is_file or script_access_path.contains("/") or script_access_path.is_absolute_path():
			return PathCompletion.files(script_access_path, ctx.context.cwd, token)
		return _target_choices(ctx.context, script_access_path)
	var commands = get_commands(true)
	commands.merge(get_flags(true))
	if script_access_path.is_empty():
		commands.merge(_target_choices(ctx.context))
	return commands


static func _target_choices(ctx:Context, prefix:String="") -> Dictionary:
	var all_classes = Utils.global_class_paths()
	var hook = ctx.host_data.get("script_targets")
	var names = hook.call() if hook is Callable and hook.is_valid() else all_classes.keys()
	var options = Options.new()
	for name in names:
		if all_classes.has(name) and str(name).begins_with(prefix):
			options.add_option(str(name))
	return options.get_options()


## Completion replaces the whole raw word. Keep quoted paths as a single shell argument.
static func _format_target_choices(choices:Dictionary, raw_value:String, flag_prefix:String="") -> Dictionary:
	for name in choices:
		if name == Options.Keys.COMMAND_META:
			continue
		var meta:Dictionary = choices[name][Options.Keys.METADATA]
		var insertion:String = meta[Options.Keys.INSERT]
		var quote = raw_value.left(1) if raw_value.left(1) in ["'", '"'] else ""
		if quote.is_empty() and (insertion.contains(" ") or insertion.contains("\t")):
			quote = '"'
		if quote == '"':
			insertion = insertion.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$")
		meta[Options.Keys.INSERT] = flag_prefix + quote + insertion + quote
	return choices


func _execute(ctx:Context):
	if not script_access_path.is_empty() and not is_instance_valid(TargetUtil.get_script_from_ctx(ctx)):
		ctx.append_error(TargetUtil.target_error(ctx))
		return ExitCode.FAIL
	if text_flag:
		var script = TargetUtil.get_script_from_ctx(ctx)
		if is_instance_valid(script):
			if not script.has_source_code():
				ctx.append_error("Script source is unavailable (for example, in a binary export).")
				return ExitCode.FAIL
			ctx.write_output(script.source_code)
		else:
			ctx.append_error(TargetUtil.target_error(ctx))
			return ExitCode.FAIL
		return ExitCode.OK
	ctx.append_output(get_help_string(true))
	return ExitCode.OK if positional_args.is_empty() else ExitCode.FAIL

