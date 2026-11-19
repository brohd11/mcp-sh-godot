extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const TargetUtil = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/target_util.gd")

const PrintRich = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/util_r/src/string/print_rich.gd")

const _ERROR_COLOR = Color("cc000c")
const _MEMBER_COLOR = Color("4d819a")

const LIST_COMMANDS_OPTIONS = ["--methods", "--signals", "--constants", "--properties", "--enums"]
const LIST_MODIFIER_OPTIONS = ["--data", "--inherited", "--pretty", "--private", "--engine"]

const LIST_OPTION_HELP = {
	"--methods": {
		"help": "List the target's methods.",
		"prop": &"method_flag",
	},
	"--signals": {
		"help": "List the target's signals.",
		"prop": &"signal_flag",
	},
	"--constants": {
		"help": "List the target's constants.",
		"prop": &"const_flag",
	},
	"--properties": {
		"help": "List the target's properties.",
		"prop": &"prop_flag",
	},
	"--enums": {
		"help": "List the target's enums.",
		"prop": &"enum_flag",
	},
	"--data": {
		"help": "Print each member's details.",
		"prop": &"data_flag",
	},
	"--inherited": {
		"help": "Include members from base scripts.",
		"prop": &"inh_flag",
	},
	"--private": {
		"help": "Include private (underscore-prefixed) members.",
		"prop": &"private_flag",
	},
	"--engine": {
		"help": "Include base scripts and live engine members (including dynamic properties).",
		"prop": &"engine_flag",
	},
	"--pretty": {
		"help": "Print on a single line rather than new-lines.",
		"prop": &"pretty_flag",
	},
}

var target_all_flag:=true
var method_flag:=false
var signal_flag:=false
var const_flag:=false
var prop_flag:=false
var enum_flag:=false

var inh_flag:=false
var private_flag:=false
var engine_flag:=false
var data_flag:=false
var pretty_flag:=false


static func get_command_name() -> String:
	return "list"


static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": TargetUtil.get_usage_string(
			"List members of the target script or live node",
			"list <options>"
		),
	})


func _get_flags() -> Dictionary:
	var options = Options.new()
	for cmd in LIST_COMMANDS_OPTIONS:
		options.add_option(cmd, {&"help": LIST_OPTION_HELP.get(cmd, {}).get("help", "")})
	options.add_separator("Modifiers")
	for cmd in LIST_MODIFIER_OPTIONS:
		options.add_option(cmd, {&"help": LIST_OPTION_HELP.get(cmd, {}).get("help", "")})
	return options.get_options()


func _process_flag(flag:String):
	var prop = LIST_OPTION_HELP.get(flag, {}).get("prop")
	if prop == null:
		return
	set(prop, true)
	if flag in LIST_COMMANDS_OPTIONS:
		target_all_flag = false


func _execute(ctx:Context):
	var script = TargetUtil.get_target(ctx)
	if not is_instance_valid(script):
		ctx.append_error(TargetUtil.target_error(ctx))
		return ExitCode.FAIL
	return list_members(ctx, script)


func list_members(ctx:Context, script) -> int:
	var pr = PrintRich.new()
	for flag in LIST_OPTION_HELP.keys():
		if not flag in LIST_COMMANDS_OPTIONS:
			continue
		var prop = LIST_OPTION_HELP.get(flag).get("prop")
		if not (get(prop) == true or target_all_flag):
			continue

		var flag_raw = flag.trim_prefix("--")
		var members = TargetUtil.get_members(script, flag_raw, private_flag, inh_flag, engine_flag)
		ctx.append_output("%s %s:" % ["Node" if script is Node else "Script", flag_raw])

		_add_to_members_to_output(ctx, members, pr, _hidden_hints(script, flag_raw, members))

	return ExitCode.OK


## Points at the flag that would reveal members the current selection leaves out.
func _hidden_hints(target, kind:String, members:Dictionary) -> Array[String]:
	var hints:Array[String] = []
	if not private_flag:
		var hidden = TargetUtil.get_members(target, kind, true, inh_flag, engine_flag).size() - members.size()
		if hidden > 0:
			hints.append("(%d private hidden, use --private)" % hidden)
	if not engine_flag and members.is_empty() and target is Node:
		if not TargetUtil.get_members(target, kind, private_flag, inh_flag, true).is_empty():
			hints.append("(use --engine for engine members)")
	return hints


func _add_to_members_to_output(ctx:Context, members:Dictionary, pr, hints:Array[String]=[]):
	if members.is_empty():
		var err_color = _ERROR_COLOR if pretty_flag else Color.TRANSPARENT
		pr.append("\tNone on target.", err_color)
		ctx.append_output(pr.get_string(true))
	elif pretty_flag and not data_flag:
		pr.append("\t" + "  ".join(members.keys()), _MEMBER_COLOR)
		ctx.append_output(pr.get_string(true))
	else:
		for m in members.keys():
			var member_color = _MEMBER_COLOR if pretty_flag else Color.TRANSPARENT
			pr.append("\t%s" % m, member_color)
			ctx.append_output(pr.get_string(true))
			if not data_flag:
				continue
			var data = members.get(m)
			if data == null:
				pr.append("\t\tNo data.")
				ctx.append_output(pr.get_string(true))
			elif data is String:
				ctx.append_output("\t\t" + data)
			elif data is Dictionary:
				for key in data.keys():
					pr.append("\t\t%s - %s" % [key, data[key]])
					ctx.append_output(pr.get_string(true))
			else:
				ctx.append_output("\t\t" + str(data))

	for hint in hints:
		ctx.append_output("\t" + hint)
	ctx.append_output("")

