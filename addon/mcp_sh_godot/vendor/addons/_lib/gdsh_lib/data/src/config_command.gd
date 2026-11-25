extends "res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/command_base.gd"
## Shared base of `data config_file get|set|check`: loading with Godot's parse error captured, and
## section/key completion after the file argument. Lives in src/, so command dirs never list it.

const ConfigData = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh_lib/data/src/config_data.gd")

## False where every positional is a file (check).
var _complete_keys := true


## {cfg} or {error}.
func _load_cfg(path:String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "File doesn't exist: " + path}
	var cfg = ConfigFile.new()
	var captured = ErrorCapture.run(cfg.load.bind(path))
	if captured.result != OK:
		return {"error": ConfigData.load_error(path, captured.result, captured.errors)}
	return {"cfg": cfg}


## Sections for the second positional, the section's keys for the third; paths for the first.
func _get_completions(completion:Completion):
	if not _complete_keys or positional_arg_index < 1 or positional_arg_index > 2:
		return super(completion)
	var path = complete_path(positional_args[0])
	var cfg = ConfigFile.new()
	# Not captured: a parse error should reach the Output panel while typing, not stop completion.
	if not FileAccess.file_exists(path) or cfg.load(path) != OK:
		return {}
	var options = Options.new()
	if positional_arg_index == 1:
		for section in cfg.get_sections():
			options.add_option(section)
	elif cfg.has_section(positional_args[1]):
		for key in cfg.get_section_keys(positional_args[1]):
			options.add_option(key)
	return options.get_options()

