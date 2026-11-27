
extends RefCounted

const SELF = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/options.gd")
const Types = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/types.gd")
const Utils = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/utils.gd")
const FlagType = Types.FlagType
const ARG_DELIMITER = "--"


var _option_dict:= {
	Keys.COMMAND_META: {}
}

func get_options():
	return _option_dict

func set_options(option_dict:Dictionary):
	_option_dict = option_dict

func merge(options, overwrite:=false):
	if options is Dictionary:
		_option_dict.merge(options, overwrite)
	elif options is SELF:
		_option_dict.merge(options.get_options(), overwrite)
	else:
		printerr("Unhandled options merge: ", options, " -> ", _option_dict)

func size():
	return _option_dict.size() - 1 # -1 to account for meta section

func add_separator(text:="", add_decorators:=true):
	if text != "" and add_decorators:
		text = "── " + text + " ──"
	Keys.add_separator(_option_dict, text)

func remove_option(option_name:String):
	_option_dict.erase(option_name)

#! keys name:String help:String positional_count:int trailing_char:String icon:Variant
#! keys get_command:Callable priority:int metadata:Dictionary arg_count:int insert:String
#! keys flag_completion:Dictionary allow_positional_paths:bool raw:bool discoverable:bool short:String
## Nested Dict: flag_completion - type, dir, ext
func add_option(option_name:String, params:={}):
	_option_dict[option_name] = get_single_option_dict(option_name, params)

#! keys i-add_option;
static func get_single_option_dict(option_name:String, params:={}) -> Dictionary:
	params.option_name = option_name # this param is not used any where, really was just for undefined 'help'
	return process_option_dict(params)

#! keys i-add_option;

static func process_option_dict(params:={}) -> Dictionary:
	var data = {}
	data.help = params.get(&"help", "No help defined for: %s" % params.get(&"option_name", "Unamed"))
	data.positional_count = params.get(&"positional_count", 0)
	data.allow_positional_paths = params.get(&"allow_positional_paths", false)
	data.priority = params.get(&"priority", 1000)

	if params.has(&"flag_completion"):
		data.flag_completion = params.flag_completion

	# One-letter alias for a boolean flag; letters group on the command line (-ir). -h is help.
	if params.has(&"short"):
		var short = str(params.short)
		var option_name = str(params.get(&"option_name", ""))
		if short.length() != 1 or not (short >= "a" and short <= "z" or short >= "A" and short <= "Z"):
			push_error("GDSh.Options: a short flag must be one letter: '%s' (%s)" % [short, option_name])
		elif short == "h":
			push_error("GDSh.Options: -h is reserved for help (%s)" % option_name)
		elif option_name.ends_with("="):
			push_error("GDSh.Options: value flags cannot have a short form (%s)" % option_name)
		else:
			data.short = short

	if params.has(&"icon"):
		data.icon = params.icon

	# Raw commands receive their argument source unparsed; see Context.collect_raw_commands.
	if params.get(&"raw", false):
		data.raw = true

	# Non-discoverable commands are omitted from top-level listings; namespaces still list them.
	if params.get(&"discoverable", true) == false:
		data.discoverable = false

	data[Keys.METADATA] = params.get(&"metadata", {})

	if params.has(&"insert"):
		data[Keys.METADATA][Keys.INSERT] = params.insert
	#data[Keys.METADATA][Keys.ARG_COUNT] = params.get(&"arg_count", -1)
	data[Keys.METADATA][Keys.TRAILING_CHAR] = params.get(&"trailing_char", " ")
	data[Keys.METADATA][Keys.ADD_ARGS] = params.get(&"add_arg_delim", false)
	data[Keys.METADATA][Keys.REPLACE_WORD] = params.get(&"replace_current_word", true)

	if params.has(&"get_command"):
		#data[Keys.METADATA].get_command = params.get_command
		data.get_command = params.get_command

	return data

func add_command_script(command):
	add_command_script_to_dict(command, _option_dict)

static func add_command_script_to_dict(command, dict:Dictionary):
	var data = command.get_self_command_data()
	if not data.has(&"get_command"):
		data[&"get_command"] = func():
			return Utils.get_loader().fresh(command).new()
	for name in [command.get_command_name()] + Array(command.get_command_aliases()):
		dict[name] = data


func show_variables():
	add_show_variables_to_dict(_option_dict)

static func add_show_variables_to_dict(dict:Dictionary):
	if not dict.has(Keys.COMMAND_META):
		dict[Keys.COMMAND_META] = {}
	dict[Keys.COMMAND_META][Keys.SHOW_VARIABLES] = true

static func add_key_to_meta(dict:Dictionary, key:StringName, value=true):
	var meta = dict.get_or_add(Keys.METADATA)
	meta[key] = value


class Keys:
	const ICON = &"ICON"
	const ICON_COLOR = &"ICON_COLOR"
	const TOOL_TIP = &"TOOL_TIP"
	const CALLABLE = &"CALLABLE"
	const METADATA = &"METADATA"
	const RADIO = &"RADIO"
	const RADIO_IS_CHECKED = &"RADIO_IS_CHECKED"
	const ID = &"ID"
	const PRIORITY = "PRIORITY"
	const DEFAULT_PRIORITY = 1000

	const SEPARATOR_STRING = "#sep"
	const _SEP_DELIM = "-&|-"

	static func add_separator(dict:Dictionary, label:="", path:="", priority:int=DEFAULT_PRIORITY):
		var string = SEPARATOR_STRING + _SEP_DELIM + label
		if path != "":
			string = path.path_join(string)
		var count = 0
		while dict.has(string):
			string = SEPARATOR_STRING + str(count) + _SEP_DELIM + label
			count += 1
		dict[string] = {METADATA: {PRIORITY: priority}}
		return string

	static func get_seperator(text:String):
		if text.begins_with(SEPARATOR_STRING):
			if text.find(_SEP_DELIM) > -1:
				return text.get_slice(_SEP_DELIM, 1)
			return ""


	const INSERT = &"INSERT"
	const ADD_ARGS = &"ADD_ARGS"
	const REPLACE_WORD = &"REPLACE_WORD"
	const TRAILING_CHAR = &"TRAILING_CHAR"
	const ARG_COUNT = &"ARG_COUNT"

	const COMMAND_META = &"COMMAND_META"
	const SHOW_VARIABLES = &"SHOW_VARIABLES"

