# Running games

[Back to README](../README.md)

Add the [mcp_sh_bridge package](https://github.com/brohd11/godot-mcp-sh-bridge) to your
project, then create its bridge node. The editor addon is not required.

```gdscript
const McpShBridge = preload("res://addons/_lib/mcp_sh_bridge/src/bridge.gd")

func _ready():
    var bridge = McpShBridge.new()
    add_child(bridge)
```

Register the `mcp_sh_godot_game` entry printed by `setup` or `--help` for your MCP
client. It sets `MCP_SH_GODOT_PORT=9511`.

- It listens on `9511` unless `port` is set, and says `godot runtime` in `list_commands`.
  `port = -1` takes any free port (`get_port()` says which). That suits a game that starts
  its own agent and passes `MCP_SH_GODOT_PORT` to it.
- Release builds don't listen unless `serve_in_release` is set: commands can run any code.
- Without a host it serves gdsh's builtins, which work on the live tree. Use
  `bridge.host = GDSh.Host.new({"command_dirs": ["res://game/commands"]})` before
  `add_child` for the game's own commands, or `bridge.host = my_console.create_host()`
  to share an existing console's context. The host can be any `GDSh.Host`.

For bridge settings and tokens, see [Configuration](configuration.md).
