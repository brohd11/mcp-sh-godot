extends RefCounted
## The commands the plugin serves: gdsh, gdsh_lib's utils, tree and editor commands, and
## bridge.json's. Built from preloads, not class names, because an export strips class_name
## from the libraries it bundles.


const UtilsManifest = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/utils/src/manifest.gd")
const TreeManifest = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tree/src/manifest.gd")
const EditorManifest = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/editor/src/manifest.gd")


## A GDSh.Host with `host_data` hooks for every request. `config` is a BridgeConfig: its
## gdshLib switch, its commandDirs/commands and the commands/ folders.
static func build(host_data:Dictionary, config):
	var host = GDSh_Host.new({"host_data": host_data})
	if config.gdsh_lib:
		# Typed variables read the script resources; the manifests' paths survive an export.
		var utils:Resource = UtilsManifest
		host.add_command_dir(utils.resource_path.get_base_dir())
		var tree:Resource = TreeManifest
		host.add_command(tree.resource_path.get_base_dir().path_join("tree.gd"))
		for ns in EditorManifest.NAMESPACES:
			host.add_command(ns.resource_path)
	# The user and project commands/ folders too: this editor host serves them.
	return config.add_commands_to(host, true)



### GDPackage Global Classes
const GDSh_Host = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/host.gd")

