extends RefCounted
## Preloads the editor, settings and resource namespaces and their commands, so exporters that
## follow preloads include them. GDSh.Load skips this file. Register the commands by adding this
## directory (cmd/) as a command folder: host.add_command_dir(Manifest.resource_path.get_base_dir()).

const EDITOR = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/editor.gd")
const SETTINGS = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/settings/settings.gd")
const RESOURCE = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/resource/resource.gd")

## The three top-level namespaces. Scripts, not path strings: an export rewrites both, but only a
## preload keeps working wherever the library lands.
const NAMESPACES = [EDITOR, SETTINGS, RESOURCE]

const COMMANDS = [
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/open/open.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/play/play.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/plugin/enable/enable.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/plugin/plugin.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/redo/redo.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/restart/restart.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/reveal/reveal.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/scan/scan.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/scene/new/new.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/scene/reload/reload.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/scene/root/root.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/scene/save/save.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/scene/scene.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/scene/select/select.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/screenshot/screenshot.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/script/script.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/search/search.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/state/state.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/stop/stop.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/editor/undo/undo.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/resource/deps/deps.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/resource/duplicate/duplicate.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/resource/new/new.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/resource/reload_script/reload_script.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/resource/search/search.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/resource/uid/uid.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/settings/esetting/esetting.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/settings/mainscene/mainscene.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/settings/psetting/psetting.gd"),
]

