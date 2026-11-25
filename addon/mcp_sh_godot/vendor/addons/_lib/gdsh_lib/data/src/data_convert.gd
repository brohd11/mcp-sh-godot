extends RefCounted
## Reads and writes data files as JSON, YAML or Godot binary (FileAccess.store_var). Static and
## editor-free, so the gdsh CLI can bundle it. YAML is preloaded by path, not its global class name,
## so the package still works where yaml_parser isn't registered (a vendored copy).

const YAML = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/yaml_parser/yaml.gd")

const JSON_FORMAT = "json"
const YAML_FORMAT = "yaml"
const BIN_FORMAT = "bin"
const YAML_EXTENSIONS = ["yml", "yaml"]


## The format a file's extension names: "json", "yaml", or "" (binary only with --from-bin).
static func format_of(path:String) -> String:
	var ext = path.get_extension().to_lower()
	if ext == "json":
		return JSON_FORMAT
	if ext in YAML_EXTENSIONS:
		return YAML_FORMAT
	return ""


## {data} or {error}. An extension other than json/yml/yaml is read as binary only when `from_bin`.
static func read(path:String, from_bin := false) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "File doesn't exist: " + path}
	match format_of(path):
		JSON_FORMAT:
			var json = JSON.new()
			if json.parse(FileAccess.get_file_as_string(path)) != OK:
				return {"error": "Invalid JSON in %s, line %d: %s" % [path, json.get_error_line(), json.get_error_message()]}
			return {"data": json.data}
		YAML_FORMAT:
			var parser = YAML.new()
			if parser.parse_file(path) != OK:
				return {"error": "Invalid YAML in %s: %s" % [path, parser.get_error_message()]}
			return {"data": parser.data}
	if not from_bin:
		return {"error": "Unrecognized extension (pass --from-bin for a binary file): " + path}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Can't open %s: %s" % [path, error_string(FileAccess.get_open_error())]}
	var data = file.get_var()
	if not (data is Dictionary or data is Array):
		return {"error": "Binary root must be a Dictionary or Array: " + path}
	return {"data": data}


## Writes `data` to `path` in `format`, making its folder. Returns an error message, or "".
static func write(data:Variant, path:String, format:String) -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	match format:
		YAML_FORMAT:
			var err = YAML.dump_to_file(data, path)
			return "" if err == OK else "Can't write %s: %s" % [path, error_string(err)]
		JSON_FORMAT, BIN_FORMAT:
			var file = FileAccess.open(path, FileAccess.WRITE)
			if file == null:
				return "Can't write %s: %s" % [path, error_string(FileAccess.get_open_error())]
			var ok = file.store_string(JSON.stringify(data, "\t")) if format == JSON_FORMAT else file.store_var(data)
			return "" if ok else "Can't write " + path
	return "Unknown format: " + format


## `path` with its extension swapped for the format's (`bin_ext` for binary).
static func default_output(path:String, format:String, bin_ext := BIN_FORMAT) -> String:
	var ext = {JSON_FORMAT: "json", YAML_FORMAT: "yml"}.get(format, bin_ext)
	return path.get_basename() + "." + ext

