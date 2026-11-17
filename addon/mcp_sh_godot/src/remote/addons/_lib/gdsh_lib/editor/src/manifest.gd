extends RefCounted
## Preloads the editor, settings and resource namespaces and their commands, so exporters that
## follow preloads include them. Add the namespaces with
## `for ns in Manifest.NAMESPACES: host.add_command(ns.resource_path)`.

const EDITOR = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/editor.gd")
const SETTINGS = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/settings/settings.gd")
const RESOURCE = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/resource/resource.gd")

## The three top-level namespaces. Scripts, not path strings: an export rewrites both, but only a
## preload keeps working wherever the library lands.
const NAMESPACES = [EDITOR, SETTINGS, RESOURCE]

const COMMANDS = [
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/open/open.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/play/play.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/plugin/enable/enable.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/plugin/plugin.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/redo/redo.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/restart/restart.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/reveal/reveal.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/scan/scan.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/scene/new/new.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/scene/reload/reload.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/scene/root/root.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/scene/save/save.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/scene/scene.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/scene/select/select.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/screenshot/screenshot.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/script/script.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/search/search.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/state/state.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/stop/stop.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/editor/undo/undo.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/resource/deps/deps.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/resource/duplicate/duplicate.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/resource/new/new.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/resource/reload_script/reload_script.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/resource/search/search.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/resource/uid/uid.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/settings/esetting/esetting.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/settings/mainscene/mainscene.gd"),
	preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/settings/psetting/psetting.gd"),
]

