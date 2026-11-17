extends RefCounted
## Resource-aware discovery preserves .gd names when scripts are remapped on export.

static func list_directory(path:String) -> PackedStringArray:
	if path.begins_with("res://"):
		return ResourceLoader.list_directory(path)
	var dir = DirAccess.open(path)
	if dir == null:
		push_error("GDSh: cannot open directory: " + path)
		return PackedStringArray()
	var entries = dir.get_files()
	for name in dir.get_directories():
		entries.append(name + "/")
	return entries

static func walk(path:String, directories:=false) -> PackedStringArray:
	var result = PackedStringArray()
	for entry in list_directory(path):
		if entry.begins_with("."):
			continue
		var full_path = path.path_join(entry.trim_suffix("/"))
		if entry.ends_with("/"):
			var dir = DirAccess.open(path)
			if dir != null and dir.is_link(full_path):
				continue
			if directories:
				result.append(full_path)
			result.append_array(walk(full_path, directories))
		elif not directories:
			result.append(full_path)
	return result

