extends RefCounted
## The builtin command scripts. Kept apart from load.gd so a plugin that only implements commands
## (CommandBase -> Utils -> Load) does not ship every builtin; GDSh.Host preloads this instead.

const Types = preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/types.gd")

const SCRIPTS = [
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/builtins.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/hidden/hidden.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/clear/clear.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/new_ctx/new_ctx.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/break/break.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/continue/continue.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/return/return.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/exit/exit.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/shift/shift.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/true/true.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/false/false.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/comparison/comparison.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/expr/expr.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/echo/echo.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/source/source.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/cd/cd.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/cn/cn.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/pwn/pwn.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/node/node.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/script/script.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/ambiguous/ambiguous.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/help/help.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/function/function.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/gdsh/gdsh.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/undoredo/undoredo.gd"),
	preload("res://addons/mcp_sh_godot/vendor/addons/_lib/gdsh/src/core/builtins/wait/wait.gd"),
]


static func load_builtins() -> Dictionary:
	var scopes = {}
	for script in SCRIPTS:
		scopes[script.get_command_name()] = {Types.ScopeDataKeys.SCRIPT: script}
	return scopes

