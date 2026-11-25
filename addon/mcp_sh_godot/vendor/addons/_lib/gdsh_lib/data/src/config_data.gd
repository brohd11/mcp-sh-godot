extends RefCounted
## ConfigFile helpers for `data config_file`: text and JSON views of a parsed file, and values
## typed on the command line. Static and editor-free, so the gdsh CLI can bundle it.

const PARSE_PREFIX = "ConfigFile parse error at "


## Why ConfigFile.load failed: Godot's logged parse error ("path:line: reason") when it was
## captured, else the error's name.
static func load_error(path:String, err:int, logged:PackedStringArray) -> String:
	for line in logged:
		var at = line.find(PARSE_PREFIX)
		if at != -1:
			return "Invalid config: " + line.substr(at + PARSE_PREFIX.length())
	return "Can't load %s: %s" % [path, error_string(err)]


## {key: value} of one section, or {section: {key: value}} of the whole file when section is "".
static func to_dict(cfg:ConfigFile, section := "") -> Dictionary:
	if not section.is_empty():
		return _section_dict(cfg, section)
	var out = {}
	for name in cfg.get_sections():
		out[name] = _section_dict(cfg, name)
	return out


## A section's `key=value` lines, values as Godot literals: the form `set FILE SECTION` reads.
static func section_text(cfg:ConfigFile, section:String) -> String:
	var lines = PackedStringArray()
	for key in cfg.get_section_keys(section):
		lines.append("%s=%s" % [key, var_to_str(cfg.get_value(section, key))])
	return "\n".join(lines)


## The whole file in cfg syntax, as Godot parsed it (duplicate keys collapsed, comments gone).
static func file_text(cfg:ConfigFile) -> String:
	var parts = PackedStringArray()
	for name in cfg.get_sections():
		var body = section_text(cfg, name)
		parts.append("[%s]" % name if body.is_empty() else "[%s]\n%s" % [name, body])
	return "\n\n".join(parts)


## A command-line value: a Godot literal (12, true, Vector2(1, 2), "12"), else the text as a String.
static func parse_value(text:String) -> Variant:
	var value = str_to_var(text)
	if value == null and text.strip_edges() != "null":
		return text
	return value


## {values: {key: value}} from `key=value` lines (blank and ;/# comment lines skipped), or {error}.
static func parse_lines(text:String) -> Dictionary:
	var values = {}
	for line in text.split("\n", false):
		var stripped = line.strip_edges()
		if stripped.is_empty() or stripped.begins_with(";") or stripped.begins_with("#"):
			continue
		var eq = stripped.find("=")
		if eq < 1:
			return {"error": "Expected key=value, got: " + stripped}
		values[stripped.left(eq).strip_edges()] = parse_value(stripped.substr(eq + 1).strip_edges())
	return {"values": values}


static func _section_dict(cfg:ConfigFile, section:String) -> Dictionary:
	var out = {}
	for key in cfg.get_section_keys(section):
		out[key] = cfg.get_value(section, key)
	return out

