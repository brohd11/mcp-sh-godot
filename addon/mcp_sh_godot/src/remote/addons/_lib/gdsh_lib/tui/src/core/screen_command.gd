
extends "res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh/src/tui/tui_command.gd"
## Override create_screen() and normal command metadata; run() remains available.
const Screen = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tui/src/core/screen.gd")
const Router = preload("res://addons/mcp_sh_godot/src/remote/addons/_lib/gdsh_lib/tui/src/core/router.gd")
var router:Router
var result:Variant
var _redraw_token = RefCounted.new()
var _redraw_pending:=false
var _updating:=false

func create_screen() -> Screen:
	return null

func update(message:TUIMsg) -> void:
	_updating = true
	if message.type == TUIMsg.Type.INIT:
		result = null
		_redraw_pending = false
		router = Router.new()
		router.redraw_requested.connect(_request_redraw)
		router.completed.connect(_completed_screen)
		router.set_size(viewport_size)
		var screen = create_screen()
		if _running:
			if screen == null or screen._finished or (screen._owner != null and screen._owner.get_ref() != null):
				context.append_error("%s: create_screen() must return a fresh, unowned screen" % get_command_name())
				quit(ExitCode.FAIL)
			else:
				router.push(screen)
	elif message.type == TUIMsg.Type.USER and is_same(message.payload, _redraw_token):
		_redraw_pending = false
	elif router != null:
		if message.type == TUIMsg.Type.RESIZE: router.set_size(viewport_size)
		if router != null: router.update(message)
	if router != null: hint = router.get_hint()
	_updating = false

func view() -> String:
	return router.view() if router != null else ""

func _request_redraw() -> void:
	if _updating or _redraw_pending or not _running: return
	_redraw_pending = true
	post_message(TUIMsg.new(TUIMsg.Type.USER, _redraw_token))

func _completed_screen(value:Variant) -> void:
	result = value
	quit()

func finish() -> void:
	if router != null:
		router.redraw_requested.disconnect(_request_redraw)
		router.completed.disconnect(_completed_screen)
		router.finish()
		router = null
	_redraw_pending = false

