extends RefCounted
## Optional read-only shell filesystem. Command/package loading stays on the resource filesystem.
## Provider methods: resolve(path, cwd), stat(path), list_dir(path), read_text(path).
## All return {ok, error, message, ...}; paths passed to operations are canonical.


static func bound(ctx) -> bool:
	return ctx.host_data.has("filesystem")


static func failure(code:int, message:String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}


static func _invoke(ctx, method:String, args:Array) -> Dictionary:
	var provider = ctx.host_data.get("filesystem")
	if not provider is Object or not is_instance_valid(provider) or not provider.has_method(method):
		return failure(ERR_INVALID_PARAMETER, "Invalid filesystem provider: missing " + method)
	var result = provider.callv(method, args)
	if not result is Dictionary or not result.get("ok") is bool \
			or not result.get("error") is int or not result.get("message") is String:
		return failure(ERR_INVALID_PARAMETER, "Invalid filesystem result from " + method)
	if result.ok:
		var valid = result.get("path") is String
		match method:
			"stat": valid = valid and result.get("kind") in ["file", "directory"] and result.get("readable") is bool
			"list_dir": valid = valid and result.get("entries") is Array
			"read_text": valid = valid and result.get("text") is String
		if not valid:
			return failure(ERR_INVALID_PARAMETER, "Invalid filesystem payload from " + method)
		if method == "list_dir":
			for entry in result.entries:
				if not entry is Dictionary or not entry.get("name") is String or not entry.get("path") is String \
						or not entry.get("kind") in ["file", "directory"] or not entry.get("readable") is bool:
					return failure(ERR_INVALID_PARAMETER, "Invalid filesystem directory entry")
	return result


static func resolve(ctx, path:String) -> Dictionary:
	if bound(ctx):
		return _invoke(ctx, "resolve", [path, ctx.cwd])
	return {"ok": true, "error": OK, "message": "", "path":
		path.simplify_path() if path.is_absolute_path() else ctx.cwd.path_join(path).simplify_path()}


static func operation(ctx, method:String, path:String) -> Dictionary:
	var resolved = resolve(ctx, path)
	if not resolved.ok:
		return resolved
	path = resolved.path
	if bound(ctx):
		return _invoke(ctx, method, [path])
	match method:
		"stat":
			var kind = "directory" if DirAccess.dir_exists_absolute(path) else "file" if FileAccess.file_exists(path) else ""
			if kind.is_empty():
				return failure(ERR_FILE_NOT_FOUND, "No such file or directory: " + path)
			return {"ok": true, "error": OK, "message": "", "path": path, "kind": kind, "readable": true}
		"read_text":
			var file = FileAccess.open(path, FileAccess.READ)
			if file == null:
				return failure(FileAccess.get_open_error(), "Cannot read file: " + path)
			return {"ok": true, "error": OK, "message": "", "path": path, "text": file.get_as_text()}
		"list_dir":
			var dir = DirAccess.open(path)
			if dir == null:
				return failure(DirAccess.get_open_error(), "Cannot list directory: " + path)
			var entries:Array[Dictionary] = []
			for name in dir.get_directories():
				entries.append({"name": name, "path": path.path_join(name), "kind": "directory", "readable": true})
			for name in dir.get_files():
				entries.append({"name": name, "path": path.path_join(name), "kind": "file", "readable": true})
			return {"ok": true, "error": OK, "message": "", "path": path, "entries": entries}
	return failure(ERR_UNAVAILABLE, "Unsupported filesystem operation: " + method)


static func walk(ctx, path:String) -> Dictionary:
	var first = operation(ctx, "list_dir", path)
	if not first.ok:
		return first
	var entries:Array = []
	var pending:Array = [first]
	while not pending.is_empty():
		var listing:Dictionary = pending.pop_back()
		for entry:Dictionary in listing.entries:
			entries.append(entry)
			if entry.kind == "directory" and entry.readable:
				var children = operation(ctx, "list_dir", entry.path)
				if children.ok:
					pending.append(children)
	entries.sort_custom(func(a, b): return a.path < b.path)
	return {"ok": true, "error": OK, "message": "", "entries": entries}

