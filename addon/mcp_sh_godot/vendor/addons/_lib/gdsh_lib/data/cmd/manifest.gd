extends RefCounted
## Preloads the data commands, so exporters that follow preloads include them. GDSh.Load skips
## this file. Register by adding this directory (cmd/) as a command folder:
## host.add_command_dir(Manifest.resource_path.get_base_dir()).

const DATA = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/data/cmd/data/data.gd")

const COMMANDS = [
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/data/cmd/data/config_file/config_file.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/data/cmd/data/config_file/check/check.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/data/cmd/data/config_file/get/get.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/data/cmd/data/config_file/set/set.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/data/cmd/data/to_bin/to_bin.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/data/cmd/data/to_json/to_json.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/data/cmd/data/to_yaml/to_yaml.gd"),
]

