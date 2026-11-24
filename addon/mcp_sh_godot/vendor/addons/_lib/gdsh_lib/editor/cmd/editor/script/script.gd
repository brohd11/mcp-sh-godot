extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/script/script.gd"
## Only base selection is editor-specific; member traversal and target commands are core's.

var editor_base:Script
var member_suffix:String

static func get_self_command_data() -> Dictionary:
	return _command_data({&"help": "Operate on the script open in the editor, optionally through inner classes.\nUsage: editor script[.Inner...] <command>"})

func _current_script() -> Script:
	var editor = Engine.get_singleton("EditorInterface")
	return editor.get_script_editor().get_current_script() if is_instance_valid(editor) else null

func _consume_self(ctx:Context) -> ExitCode:
	var token:String = _consume_token(ctx)
	script_access_path = token
	editor_base = _current_script()
	member_suffix = token.trim_prefix("script.") if token.begins_with("script.") else ""
	ctx.data.erase("node")
	ctx.data["script"] = TargetUtil.resolve_members(editor_base, member_suffix)
	if token.ends_with("."):
		ctx.data["script"] = null
	ctx.data["script_error"] = "No script open in the editor." if editor_base == null else "Could not resolve editor script target: " + token
	return ExitCode.OK

func _get_commands() -> Dictionary:
	return get_target_commands()

func _get_flags() -> Dictionary:
	return {"--text": super._get_flags()["--text"]}

func _get_completions(ctx:Completion):
	if ctx.token_before_cursor == script_access_path and ctx.char_before_cursor not in [" ", "\t", "\n"]:
		if script_access_path.begins_with("script."):
			return TargetUtil.complete_members(editor_base, member_suffix, "script.")
		return {}
	if "--text" in consumed_tokens:
		return {}
	var commands = get_commands(true)
	commands.merge(get_flags(true))
	return commands

