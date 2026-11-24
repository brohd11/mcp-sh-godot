extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"


const Pr = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/util_r/src/string/print_rich.gd")

const _PRINT_LIST_OPTIONS = ["--tool", "--abstract", "--name=", "--lang=", "--base="]
const _PRINT_LIST_HELP = {
	"--tool": "Only list tool classes.",
	"--abstract": "Only list abstract classes.",
	"--name=": "Filter class name: exact, prefix*, *suffix, or *substring*.",
	"--lang=": "Filter by script language (default GDScript).",
	"--base=": "Filter base class: exact, prefix*, *suffix, or *substring*.",
}

var show_abstract:= false
var show_tool:= false
var target_name:String = "--"
var target_language:String="GDScript"
var target_base:String = "--"

static func get_command_name() -> String:
	return "list_global"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": "List global classes\nUsage: script list_global <options>",
	})


func _get_flags() -> Dictionary:
	var options = Options.new()
	for arg in _PRINT_LIST_OPTIONS:
		if arg.ends_with("="):
			options.add_option(arg, {
				&"help": _PRINT_LIST_HELP.get(arg, ""),
				&"trailing_char": ""
			})
		else:
			options.add_option(arg, {
				&"help": _PRINT_LIST_HELP.get(arg, "")
			})
	return options.get_options()

func _process_flag(flag:String):
	if flag in ["-t", "--tool"]:
		show_tool = true
	elif flag in ["-a", "--abstract"]:
		show_abstract = true
	elif flag.begins_with("--name="):
		target_name = flag.get_slice("--name=", 1)
		target_name = Utils.unquote(target_name)
	elif flag.begins_with("--lang="):
		target_language = flag.get_slice("--lang=", 1)
		target_language = Utils.unquote(target_language)
	elif flag.begins_with("--base="):
		target_base = flag.get_slice("--base=", 1)
		target_base = Utils.unquote(target_base)
	else:
		_ctx_obj.append_error("Unrecognized argument: " + flag)


func _get_completions(ctx:Completion):
	if ctx.token_before_cursor.contains("=") and ctx.char_before_cursor != " ":
		return {}
	return get_flags(true)

func _execute(ctx:Context):
	_print_list(ctx)
	return ExitCode.OK

# global commands
func _print_list(ctx:Context):
	var name_check:TextCheck
	if target_name != "--":
		name_check = TextCheck.new(target_name)

	var base_check:TextCheck
	if target_base != "--":
		base_check = TextCheck.new(target_base)
	var did_print = false
	ctx.append_output("Printing global class list:")
	var pr = Pr.new()
	var global_class_list = ProjectSettings.get_global_class_list()
	for data:Dictionary in global_class_list:
		var name = data.get("class")
		var base = data.get("base")
		var language = data.get("language")
		var is_tool = data.get("is_tool")
		var is_abstract = data.get("is_abstract")

		if show_tool and not is_tool:
			continue
		if show_abstract and not is_abstract:
			continue
		if target_language != language:
			continue

		if is_instance_valid(name_check):
			if not name_check.check_text(name):
				continue
		if is_instance_valid(base_check):
			if not base_check.check_text(base):
				continue

		did_print = true


		ctx.append_output("")
		ctx.append_output(pr.append(name, Color("4d819a")).get_string(true))

		for key:String in data.keys():
			ctx.append_output(pr.append("\t" + str(key), Color.SKY_BLUE).append(": ").append(str(data[key])).get_string(true))

	if not did_print:
		ctx.append_output("No classes to show.")


class TextCheck:

	var target_text_raw:String
	var _target_text:String

	var check_begin:bool
	var check_end:bool

	func _init(target_text:String) -> void:
		target_text_raw = target_text
		check_begin = target_text_raw.ends_with("*")
		check_end = target_text_raw.begins_with("*")
		_target_text = target_text_raw.trim_prefix("*").trim_suffix("*")

	func check_text(text:String):
		var valid_text = false
		if check_begin and check_end:
			valid_text = text.contains(_target_text)
		elif check_begin:
			valid_text = text.begins_with(_target_text)
		elif check_end:
			valid_text = text.ends_with(_target_text)
		else:
			valid_text = _target_text == text
		return valid_text

