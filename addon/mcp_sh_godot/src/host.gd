extends RefCounted
## The commands the plugin serves: gdsh, gdsh_lib's utils, tree and editor commands, the
## ~/.gdsh, res://.gdsh and .mcp-sh/godot command roots, and bridge.json's. Built from preloads, not class names,
## because an export strips class_name from the libraries it bundles.


const UtilsManifest = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/cmd/manifest.gd")
const TreeManifest = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/cmd/manifest.gd")
const EditorManifest = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/cmd/manifest.gd")


## A GDSh.Host with `host_data` hooks for every request. `config` is a BridgeConfig: its
## gdshLib switch, its commandDirs/commands and the command roots.
static func build(host_data:Dictionary, config):
	var host = GDSh_Host.new({"host_data": host_data})
	if config.gdsh_lib:
		# Each manifest sits in its package's cmd/ dir; its path survives an export.
		for manifest:Resource in [UtilsManifest, TreeManifest, EditorManifest]:
			host.add_command_dir(manifest.resource_path.get_base_dir())
	# The command roots too: this editor host serves them.
	return config.add_commands_to(host, true)



### GDPackage Global Classes
const GDSh_Host = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/host.gd")

