
extends RefCounted
## Undoable changes for commands. Get an Action from `ctx.undo_action(name)`:
##
##   var a = ctx.undo_action("Rename node")
##   a.do_property(node, &"name", new_name)
##   a.undo_property(node, &"name", old_name)
##   a.commit()
##
## commit() replays the operations into the host's undo object (an UndoRedo, or any object
## with UndoRedo's add_do_*/add_undo_* methods taking (object, method, args...)), which runs
## the do side. Without one, commit() applies the do side directly. Commands must NOT also
## apply the change themselves.
##
## While a compound Session is open (`undoredo --compound`), commit() applies the do side
## directly and buffers the operations; `undoredo commit` registers everything buffered as
## one action without re-running it, so later commands see earlier changes.

enum {
	_DO_PROPERTY,
	_UNDO_PROPERTY,
	_DO_METHOD,
	_UNDO_METHOD,
	_DO_REFERENCE,
	_UNDO_REFERENCE,
}


class Action:
	extends RefCounted

	var _name:String
	var _undo_redo:Object
	var _session:Session
	var _ops:Array = []

	func _init(name:String, undo_redo:Object=null, session:Session=null) -> void:
		_name = name
		_undo_redo = undo_redo
		_session = session

	func do_property(obj:Object, property:StringName, value):
		_ops.append([_DO_PROPERTY, obj, property, value])
		return self

	func undo_property(obj:Object, property:StringName, value):
		_ops.append([_UNDO_PROPERTY, obj, property, value])
		return self

	func do_method(obj:Object, method:StringName, args:Array = []):
		_ops.append([_DO_METHOD, obj, method, args])
		return self

	func undo_method(obj:Object, method:StringName, args:Array = []):
		_ops.append([_UNDO_METHOD, obj, method, args])
		return self

	## Object is out of the tree on the do side (a new node before add_child): the undo
	## stack keeps it alive so an undo can restore it.
	func do_reference(obj:Object):
		_ops.append([_DO_REFERENCE, obj])
		return self

	## Object is out of the tree on the undo side (a removed node): the undo stack keeps it.
	## Without an undo object there is nothing to restore, so commit() frees it.
	func undo_reference(obj:Object):
		_ops.append([_UNDO_REFERENCE, obj])
		return self

	func commit() -> void:
		if _ops.is_empty():
			return
		if _session != null and _session.is_open():
			_session.add(_ops)
		elif is_instance_valid(_undo_redo):
			Ops.replay(_undo_redo, _name, [_ops], true)
		else:
			Ops.apply(_ops, _DO_PROPERTY, _DO_METHOD)
			Ops.free_references([_ops], _UNDO_REFERENCE)


## Buffer for a compound action, shared through `ctx.host_data["undo_session"]`. Changes are
## applied as each command commits; commit() or cancel() ends the outermost level.
class Session:
	extends RefCounted

	var name:String
	var depth:int = 0
	## One op list per committed Action, in commit order.
	var groups:Array = []

	func is_open() -> bool:
		return depth > 0

	## Nested begins keep the outermost name.
	func begin(action_name:String) -> void:
		if depth == 0:
			name = action_name
			groups.clear()
		depth += 1

	## Apply an Action's do side now and keep its operations for the compound entry.
	func add(ops:Array) -> void:
		Ops.apply(ops, _DO_PROPERTY, _DO_METHOD)
		groups.append(ops)

	## Close one level. The outermost registers the buffered changes on undo_redo as one action
	## (already applied, so not re-run); without undo_redo they stay applied untracked.
	## Returns true when the compound ended.
	func commit(undo_redo:Object, action_name:="") -> bool:
		if depth == 0:
			return false
		depth -= 1
		if depth > 0:
			return false
		if not action_name.is_empty():
			name = action_name
		if not groups.is_empty():
			if is_instance_valid(undo_redo):
				Ops.replay(undo_redo, name, groups, false)
			else:
				Ops.free_references(groups, _UNDO_REFERENCE)
		groups.clear()
		return true

	## Revert every buffered change, last command first, and end the compound at any depth.
	func cancel() -> void:
		for i in range(groups.size() - 1, -1, -1):
			Ops.apply(groups[i], _UNDO_PROPERTY, _UNDO_METHOD)
		Ops.free_references(groups, _DO_REFERENCE)
		groups.clear()
		depth = 0

	func change_count() -> int:
		return groups.size()


class Ops:
	## Register groups as one action. Do ops run in commit order; undo ops run last group
	## first, so each command's undo sees the state it was recorded against.
	static func replay(ur:Object, action_name:String, op_groups:Array, execute:bool) -> void:
		# UndoRedo takes Callables; other undo managers take (object, method, args...).
		var callables = ur is UndoRedo
		ur.create_action(action_name)
		for ops in op_groups:
			_add_ops(ur, ops, callables, [_DO_PROPERTY, _DO_METHOD, _DO_REFERENCE, _UNDO_REFERENCE])
		for i in range(op_groups.size() - 1, -1, -1):
			_add_ops(ur, op_groups[i], callables, [_UNDO_PROPERTY, _UNDO_METHOD])
		ur.commit_action(execute)

	static func _add_ops(ur:Object, ops:Array, callables:bool, kinds:Array) -> void:
		for op in ops:
			if not op[0] in kinds or not is_instance_valid(op[1]):
				continue
			match op[0]:
				_DO_PROPERTY:
					ur.add_do_property(op[1], op[2], op[3])
				_UNDO_PROPERTY:
					ur.add_undo_property(op[1], op[2], op[3])
				_DO_METHOD:
					if callables:
						ur.add_do_method(Callable(op[1], op[2]).bindv(op[3]))
					else:
						ur.callv("add_do_method", [op[1], op[2]] + op[3])
				_UNDO_METHOD:
					if callables:
						ur.add_undo_method(Callable(op[1], op[2]).bindv(op[3]))
					else:
						ur.callv("add_undo_method", [op[1], op[2]] + op[3])
				_DO_REFERENCE:
					ur.add_do_reference(op[1])
				_UNDO_REFERENCE:
					ur.add_undo_reference(op[1])

	## Run one side's property and method ops directly, in order.
	static func apply(ops:Array, property_kind:int, method_kind:int) -> void:
		for op in ops:
			if not is_instance_valid(op[1]):
				continue
			if op[0] == property_kind:
				op[1].set(op[2], op[3])
			elif op[0] == method_kind:
				op[1].callv(op[2], op[3])

	## Free the referenced objects that no undo stack will keep: nodes left outside the tree
	## and non-RefCounted objects.
	static func free_references(op_groups:Array, kind:int) -> void:
		var seen := {}
		for ops in op_groups:
			for op in ops:
				if op[0] != kind or not is_instance_valid(op[1]) or seen.has(op[1]):
					continue
				var obj = op[1]
				seen[obj] = true
				if obj is Node:
					if obj.get_parent() == null:
						obj.queue_free()
				elif not obj is RefCounted:
					obj.free()

