
@tool
extends RefCounted
## The cfg that makes a dir a package, shared with gdaddon: the first of NAMES found is the only one
## read. Package keys live in [package], [addon] or [plugin], earlier winning key by key, so a
## plugin.cfg keeps Godot's [plugin] keys beside package metadata. addon.cfg, version.cfg and
## [addon] are legacy, read until packages migrate. New keys go to [plugin] for now.

const NAMES = ["plugin.cfg", "package.cfg", "addon.cfg", "version.cfg"] # lookup order
const SECTIONS = ["package", "addon", "plugin"] # precedence order
const DEFAULT_SECTION = "plugin"


## Path of the package cfg in `dir`, or "".
static func find(dir:String) -> String:
	for nm in NAMES:
		var path = dir.path_join(nm)
		if FileAccess.file_exists(path):
			return path
	return ""


## Every package cfg in `dir`, in NAMES order. More than one is a mistake: only the first is read.
static func find_all(dir:String) -> Array[String]:
	var out:Array[String] = []
	for nm in NAMES:
		var path = dir.path_join(nm)
		if FileAccess.file_exists(path):
			out.append(path)
	return out


static func has_cfg(dir:String) -> bool:
	return find(dir) != ""


## Raw `key=value` strings of the package sections, merged by SECTIONS precedence. Hand-read
## rather than ConfigFile, which rejects values gdaddon's ini reader accepts.
static func section(text:String) -> Dictionary:
	var by_section = _sections(text)
	var keys = {}
	for i in range(SECTIONS.size() - 1, -1, -1):
		keys.merge(by_section.get(SECTIONS[i], {}), true)
	return keys


## The section a write of `key` belongs in: the first in SECTIONS already holding it, else
## DEFAULT_SECTION.
static func key_section(text:String, key:String) -> String:
	var by_section = _sections(text)
	for s in SECTIONS:
		if by_section.get(s, {}).has(key):
			return s
	return DEFAULT_SECTION


static func get_value(cfg:ConfigFile, key:String, default = null):
	for s in SECTIONS:
		if cfg.has_section_key(s, key):
			return cfg.get_value(s, key)
	return default


## `key`'s value from `dir`'s package cfg, or `default` when there is no cfg, it won't parse, or
## neither section has the key.
static func dir_value(dir:String, key:String, default = null):
	var path = find(dir)
	if path == "":
		return default
	var cfg = ConfigFile.new()
	if cfg.load(path) != OK:
		return default
	return get_value(cfg, key, default)


## `text` with every package section's `require` (or legacy `deps`) list set to `specs`; everything
## else is left byte for byte. One line by default; `multiline` writes one spec per line with a
## trailing comma, gdaddon's style, for hand-kept lists. With neither key, an empty `specs` changes
## nothing and a non-empty one is added to the section holding version=.
static func set_require(text:String, specs:Array, multiline:bool = false) -> String:
	var quoted = specs.map(func(s): return '"%s"' % s)
	var value = "[%s]" % ", ".join(quoted)
	if multiline and not specs.is_empty():
		value = "[\n%s,\n]" % ",\n".join(quoted)
	var out:Array[String] = []
	var current = ""
	var replaced = false
	var skipping = false # inside a replaced multi-line array
	for line in text.split("\n"):
		if skipping:
			skipping = not "]" in line
			continue
		var stripped = line.strip_edges()
		if stripped.begins_with("["):
			current = stripped.trim_prefix("[").trim_suffix("]").strip_edges()
		elif current in SECTIONS and "=" in stripped and stripped.get_slice("=", 0).strip_edges() in ["require", "deps"]:
			var old_value = stripped.substr(stripped.find("=") + 1)
			out.append("%s=%s" % [stripped.get_slice("=", 0).strip_edges(), value])
			replaced = true
			skipping = "[" in old_value and not "]" in old_value
			continue
		out.append(line)
	if replaced or specs.is_empty():
		return "\n".join(out)

	var target = key_section(text, "version")
	var header = -1
	var last = -1 # last non-blank line of the target section
	for i in out.size():
		var stripped = out[i].strip_edges()
		if stripped.begins_with("["):
			if header >= 0:
				break
			if stripped.trim_prefix("[").trim_suffix("]").strip_edges() == target:
				header = i
				last = i
		elif header >= 0 and stripped != "":
			last = i
	if header < 0:
		out.append_array(["", "[%s]" % target, "require=" + value])
	else:
		out.insert(last + 1, "require=" + value)
	return "\n".join(out)


## `text` with `key="value"` set: replaced in place wherever a package section holds it, else
## inserted right after version= (end of that section without one). Single-line values only.
static func set_value(text:String, key:String, value:String) -> String:
	var line_text = '%s="%s"' % [key, value]
	var lines = text.split("\n")
	var replaced = false
	for i in _key_lines(lines, key):
		lines[i] = line_text
		replaced = true
	if replaced:
		return "\n".join(lines)

	var target = key_section(text, "version")
	var header = -1
	var anchor = -1 # version= line, else last non-blank line of the target section
	var current = ""
	for i in lines.size():
		var stripped = lines[i].strip_edges()
		if stripped.begins_with("["):
			if header >= 0 and current == target:
				break
			current = stripped.trim_prefix("[").trim_suffix("]").strip_edges()
			if current == target:
				header = i
				anchor = i
			continue
		if current != target or stripped == "":
			continue
		if stripped.get_slice("=", 0).strip_edges() == "version":
			anchor = i
			break
		anchor = i
	if header < 0:
		lines.append_array(["", "[%s]" % target, line_text])
	else:
		lines.insert(anchor + 1, line_text)
	return "\n".join(lines)


## `text` without any package-section `key=` line. Single-line values only.
static func remove_value(text:String, key:String) -> String:
	var lines = Array(text.split("\n"))
	var drop = _key_lines(PackedStringArray(lines), key)
	drop.reverse()
	for i in drop:
		lines.remove_at(i)
	return "\n".join(lines)


static func _key_lines(lines:PackedStringArray, key:String) -> Array:
	var out = []
	var current = ""
	for i in lines.size():
		var stripped = lines[i].strip_edges()
		if stripped.begins_with("["):
			current = stripped.trim_prefix("[").trim_suffix("]").strip_edges()
		elif current in SECTIONS and "=" in stripped and stripped.get_slice("=", 0).strip_edges() == key:
			out.append(i)
	return out


static func _sections(text:String) -> Dictionary:
	var out = {}
	var current = ""
	for line in text.split("\n"):
		line = line.strip_edges()
		if line.begins_with("["):
			current = line.trim_prefix("[").trim_suffix("]").strip_edges()
			continue
		if not current in SECTIONS or line == "" or line.begins_with(";") or not "=" in line:
			continue
		if not out.has(current):
			out[current] = {}
		out[current][line.get_slice("=", 0).strip_edges()] = line.substr(line.find("=") + 1).strip_edges()
	return out

