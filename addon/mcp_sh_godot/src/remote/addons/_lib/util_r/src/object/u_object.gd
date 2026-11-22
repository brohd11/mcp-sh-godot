

static func instance_scene_or_script(path:String):
	if not FileAccess.file_exists(path):
		print("Could not instance, file doesn't exist: %s" % path)
		return
	var res = load(path)
	if res is PackedScene:
		var ins = res.instantiate()
		return ins
	elif res is Script:
		var ins = res.new()
		return ins
	else:
		print("Could not instance file: %s, file is: %s" % [path, type_string(typeof(res))])

static func get_object_file_path(obj:Object) -> String:
	if obj is Node:
		if obj.scene_file_path != "":
			return obj.scene_file_path
	if obj is Resource:
		return obj.resource_path
	else:
		var script = obj.get_script()
		if script:
			return script.resource_path
	return ""

