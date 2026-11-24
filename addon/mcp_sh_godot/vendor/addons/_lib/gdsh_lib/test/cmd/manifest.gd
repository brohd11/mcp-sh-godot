extends RefCounted
## Preloads the test command, so exporters that follow preloads include it. GDSh.Load skips this
## file. Register by adding this directory (cmd/) as a command folder:
## host.add_command_dir(Manifest.resource_path.get_base_dir()).

const COMMANDS = [
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/test/cmd/test/test.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/test/cmd/gdtest/gdtest.gd"),
]

