extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/command_base.gd"

const _HELP = \
"Capture the editor to a PNG and print its absolute path (so an agent can read it back).
Default captures the full editor window. Output path is an optional arg
(res:// or user://); defaults to user://console_screenshots/editor_<timestamp>.png.
Usage: editor screenshot [out_path] [--viewport-2d|--viewport-3d|--game]"

var viewport_2d_flag := false
var viewport_3d_flag := false
var game_flag := false

static func get_command_name() -> String:
	return "screenshot"

static func get_self_command_data() -> Dictionary:
	return _command_data({
		&"help": _HELP,
		&"positional_count": "min:0,max:1",
	})

func _get_flags() -> Dictionary:
	var options = Options.new()
	options.add_option("--viewport-2d", {&"help": "Capture only the 2D editor viewport."})
	options.add_option("--viewport-3d", {&"help": "Capture only the 3D editor viewport."})
	options.add_option("--game", {&"help": "Capture the running game window (requires a playing scene)."})
	return options.get_options()

func _process_flag(flag:String):
	if flag == "--viewport-2d":
		viewport_2d_flag = true
	elif flag == "--viewport-3d":
		viewport_3d_flag = true
	elif flag == "--game":
		game_flag = true

func _execute(ctx:Context):
	var viewport:Viewport = _pick_viewport(ctx)
	if not is_instance_valid(viewport):
		return ExitCode.FAIL

	var image:Image = _capture(viewport)
	if not is_instance_valid(image) or image.is_empty():
		# A single forced redraw usually populates the viewport texture.
		RenderingServer.force_draw()
		image = _capture(viewport)
	if not is_instance_valid(image) or image.is_empty():
		ctx.append_error("Could not capture the viewport image.")
		return ExitCode.FAIL

	var path := _resolve_out_path()
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var err := image.save_png(path)
	if err != OK:
		ctx.append_error("Failed to save PNG (%s): %s" % [error_string(err), path])
		return ExitCode.FAIL

	ctx.append_output(ProjectSettings.globalize_path(path))
	return ExitCode.OK

func _pick_viewport(ctx:Context) -> Viewport:
	if game_flag:
		if not EditorInterface.is_playing_scene():
			ctx.append_error("--game requires a running scene (none is playing).")
			return null
		# The running game lives in its own OS window/process; the editor can only
		# capture surfaces it owns. Fall back to the editor's main viewport with a note.
		ctx.append_error("Note: the running game runs in a separate window; capturing the editor instead.")
		return EditorInterface.get_base_control().get_viewport()
	if viewport_2d_flag:
		return EditorInterface.get_editor_viewport_2d()
	if viewport_3d_flag:
		return EditorInterface.get_editor_viewport_3d(0)
	return EditorInterface.get_base_control().get_viewport()

func _capture(viewport:Viewport) -> Image:
	var tex := viewport.get_texture()
	if not is_instance_valid(tex):
		return null
	return tex.get_image()

func _resolve_out_path() -> String:
	if not positional_args.is_empty() and positional_args[0].strip_edges() != "":
		var p = positional_args[0].strip_edges()
		if p.get_extension().to_lower() != "png":
			p += ".png"
		return p
	return "user://console_screenshots/editor_%d.png" % Time.get_unix_time_from_system()

