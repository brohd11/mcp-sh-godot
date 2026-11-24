

const UEngine = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/util_r/src/u_engine.gd") #! resolve UtilR.UEngine

var ur:UndoRedo

func _init(undo_redo:UndoRedo):
	ur = undo_redo

static func _get_undo_redo(_ur=null):
	if is_instance_valid(_ur):
		return _ur
	var ed_interface = UEngine.get_editor_interface()
	if is_instance_valid(ed_interface):
		return ed_interface.get_editor_undo_redo()
	return null

func property(action_name:String, object, property_name:StringName, new_val, prev_val):
	property_action(action_name, object, property_name, new_val, prev_val, ur)

static func property_action(action_name:String, object:Object, property_name:StringName, new_val:Variant, prev_val:Variant, undo_redo=null):
	var undo = _get_undo_redo(undo_redo)
	if not is_instance_valid(undo):
		return
	
	undo.create_action(action_name)
	
	undo.add_do_property(object, property_name, new_val)
	undo.add_undo_property(object, property_name, prev_val)
	undo.commit_action()

