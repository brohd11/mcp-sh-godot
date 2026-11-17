extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Print a snapshot of the editor's current state (orientation for an agent):
edited scene, open scenes, selection, main scene, play state, current script.
Usage: editor state [--json]"

const _KEY_COLOR = Color(0.302, 0.5059, 0.6039) # the console's ACCENT_MUTE

var json_flag := false

static func get_command_name() -> String:
	return "state"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": 0,
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--json", {&"help": "Emit a single JSON object instead of labeled lines."})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--json":
		json_flag = true

func _execute(ctx:Context):
	var data = _gather()
	if json_flag:
		ctx.append_output(JSON.stringify(data, "  "))
		return ExitCode.OK

	ctx.append_output(_kv("edited_scene", data.edited_scene))
	ctx.append_output(_kv("main_scene", data.main_scene))
	ctx.append_output(_kv("playing", str(data.playing)))
	if data.playing_scene != "":
		ctx.append_output(_kv("playing_scene", data.playing_scene))
	ctx.append_output(_kv("current_script", data.current_script))

	ctx.append_output(Utils.color_text("open_scenes (%s):" % data.open_scenes.size(), Types.Colors.SCOPE))
	for s in data.open_scenes:
		ctx.append_output("  " + s)

	ctx.append_output(Utils.color_text("selection (%s):" % data.selection.size(), Types.Colors.SCOPE))
	for s in data.selection:
		ctx.append_output("  " + s)

	return ExitCode.OK

func _gather() -> Dictionary:
	var root = EditorInterface.get_edited_scene_root()
	var edited_scene := ""
	if is_instance_valid(root):
		edited_scene = root.scene_file_path

	var selection := []
	if is_instance_valid(root):
		for n in EditorInterface.get_selection().get_selected_nodes():
			selection.append(str(root.get_path_to(n)))

	var open_scenes := []
	for s in EditorInterface.get_open_scenes():
		open_scenes.append(s)

	var current_script := ""
	var script_editor = EditorInterface.get_script_editor()
	if is_instance_valid(script_editor):
		var sc = script_editor.get_current_script()
		if is_instance_valid(sc):
			current_script = sc.resource_path

	var playing := EditorInterface.is_playing_scene()
	return {
		"edited_scene": edited_scene,
		"open_scenes": open_scenes,
		"selection": selection,
		"main_scene": str(ProjectSettings.get_setting("application/run/main_scene", "")),
		"playing": playing,
		"playing_scene": EditorInterface.get_playing_scene() if playing else "",
		"current_script": current_script,
	}

func _kv(key:String, value:String) -> String:
	return Utils.color_text(key, _KEY_COLOR) + ": " + (value if value != "" else "(none)")

