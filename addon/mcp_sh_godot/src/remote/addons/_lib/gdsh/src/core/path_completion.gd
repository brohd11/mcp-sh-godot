extends RefCounted
## Filesystem completion and shell-safe insertion shared with node paths.

const Options = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/options.gd")
const Paths = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/core/paths.gd")


static func files(path:String, cwd:String, raw_word:String="") -> Dictionary:
	var options = Options.new()
	var prefix = path.left(path.rfind("/") + 1)
	var target_dir = cwd if prefix.is_empty() else prefix if prefix.is_absolute_path() else cwd.path_join(prefix).simplify_path()
	var dir = DirAccess.open(target_dir)
	if dir == null:
		return options.get_options()
	add_path_option(options, "..", prefix, raw_word)
	for name in dir.get_directories():
		add_path_option(options, name, prefix, raw_word)
	# ResourceLoader keeps original names for exported scripts; DirAccess adds plain files.
	var names = {}
	for entry in Paths.list_directory(target_dir):
		if not entry.ends_with("/"):
			names[entry] = true
	for name in dir.get_files():
		if not name.get_extension() in ["remap", "import", "uid", "gdc"]:
			names[name] = true
	var sorted_names = names.keys()
	sorted_names.sort()
	for name in sorted_names:
		if not str(name).begins_with("."):
			add_path_option(options, name, prefix, raw_word, " ")
	return options.get_options()


static func add_path_option(options:Options, name:String, prefix:String, raw_word:String, trailing:String="/") -> void:
	var insertion = prefix + name
	var quote = raw_word.left(1) if raw_word.left(1) in ["'", '"'] else ""
	if quote.is_empty():
		for character in insertion:
			if character in " \t\r\n$'\";|&()<>#\\":
				quote = '"'
				break
	# The slash belongs inside the quotes so accepting again keeps a single path argument.
	if not quote.is_empty():
		if trailing == "/":
			insertion += trailing
		if quote == '"':
			insertion = insertion.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$")
		elif insertion.contains("'"):
			insertion = insertion.replace("'", "'\\''")
		insertion = quote + insertion + quote
		if trailing == "/":
			trailing = ""
	options.add_option(name, {&"insert": insertion, &"trailing_char": trailing})

