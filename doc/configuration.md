# Configuration

[Back to README](../README.md)

## Bridge settings

Editor Console and the addon read `~/.mcp-sh/godot/bridge.json`, then
`res://.mcp-sh/godot/bridge.json`. Later files win, and `commandDirs`/`exclude` add up. Each
file's folder is a command root (`commands/` + `packages/<name>/cmd`), read before its
`commandDirs` (see [Custom commands](custom-commands.md)). Use
Project > Tools > Restart mcp-sh-godot Bridge (or `mcp --stop; mcp --start` in Editor Console)
after editing them. `autostart` and `gdshLib` are the addon's keys only. `newCommands` is
read only by `mcp_sh_godot gdsh new`, and only from the user file.

```json
{
  "port": 0,
  "token": "",
  "autostart": true,
  "gdshLib": true,
  "commandDirs": ["res://tools/agent"],
  "commands": {"bake": "res://tools/bake_command.gd"},
  "exclude": ["settings"],
  "include": ["echo"],
  "maxRequestBytes": 1048576,
  "maxConnections": 8,
  "idleTimeoutMs": 10000,
  "newCommands": "mcp-sh"
}
```

- `commandDirs` are gdsh command folders. `commands` maps a name to one command script.
  Relative paths are relative to the config file, and `~/` is the home folder.
- `newCommands`: where `gdsh new` writes. `mcp-sh` (default) uses `~/.mcp-sh/godot/commands`,
  and `gdsh` uses `~/.gdsh/commands`, which Editor Console reads too. Set it with
  `mcp_sh_godot gdsh target`.
- `port` 0 is 9510 in the editor; -1 is any free port.
- `maxRequestBytes` rejects oversized request lines with "Request too large".
  `maxConnections` caps active and waiting connections; excess connections close immediately.
  `idleTimeoutMs` drops connections that have not sent a complete request in time; it does
  not limit running commands. Defaults are shown above.
- `exclude` hides commands. The defaults hide gdsh's session builtins, the text tools the
  shell already has (`grep`, `head`, `tail`) and `os`/`term`. `include` brings a default back.
- With a token, set the same one for the shell: `MCP_SH_GODOT_TOKEN`. A different port needs
  `MCP_SH_GODOT_PORT`. The editor also reads both variables as defaults, if it was started
  with them.

Shell overrides go in `~/.mcp-sh/godot/config.json` (or `./.mcp-sh/godot.json` for one
project). See the core [configuration reference](https://github.com/brohd11/mcp-sh/blob/main/doc/configuration.md).

## Editor Console alternative

With [Editor Console](https://github.com/brohd11/Godot-Editor-Console), run
`mcp --start` in the console or add it to startup commands. The console requires
the bridge package and serves its own commands in its context (`.gdrc`, undo stack),
taking turns with console input. The bundled addon disables itself when Editor
Console is enabled.

## Addon maintenance

```sh
mcp_sh_godot addon status
mcp_sh_godot update
mcp_sh_godot addon install
```

Run addon commands from the Godot project folder. `addon status` compares installed
and bundled versions and reports Editor Console. Reinstall the addon after updating
the binary. Use `addon remove` to uninstall it.

## Command context

Arguments arrive exactly as bash passes them; gdsh quoting, variables and aliases do
not apply. `cd`/`pwd` are gdsh's working directory commands; `cn`/`pwn` manage its working
node. Both contexts persist between calls, separate from the console prompt. Use
absolute paths or check the current context before working.

Run `mcp_sh_godot commands` to check the connection. If it fails, check plugin
activation (or `mcp --start` in Editor Console) and matching port/token settings.
