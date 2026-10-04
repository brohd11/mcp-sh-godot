# mcp-sh-godot

A sandboxed bash shell over the live Godot editor, served over MCP. Built on
[mcp-sh](https://github.com/brohd11/mcp-sh). The binary carries its own editor
addon, a native mcp-sh host on `127.0.0.1:9510`. The agent runs the editor's
[gdsh](https://github.com/brohd11/godot-gdsh) commands with pipes, loops and jq.

```sh
mcp-sh-godot run 'tree root | tree nodes --recursive | grep -c Camera'
```

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/brohd11/mcp-sh-godot/main/install.sh | sh
mcp-sh-godot setup        # ~/.mcp-sh/godot/ + `claude mcp add -s user mcp-sh-godot -- <path>`
```

On Windows: `irm https://raw.githubusercontent.com/brohd11/mcp-sh-godot/main/install.ps1 | iex`.

Then, in each Godot project:

```sh
mcp-sh-godot addon install    # writes res://addons/mcp_sh_godot/, versioned with this binary
mcp-sh-godot addon status     # addon vs binary version, gdsh, editor_console
mcp-sh-godot commands         # check what the shell can reach
```

Enable **mcp-sh-godot** in Project Settings > Plugins. It listens while the editor is open.
Run `mcp-sh-godot addon install` again after `mcp-sh-godot update`, so the addon matches the
binary. `addon remove` takes it out.

The addon needs gdsh in `res://addons/addon_lib/gdsh` (`gdaddon install brohd11/godot-gdsh`).
Which commands it offers:

- With [Editor Console](https://github.com/brohd11/Godot-Editor-Console) enabled, its
  commands are offered. They run in the console's context (aliases, `.gdrc`, the undo
  stack), taking turns with what you type into it.
- Without it, gdsh's own commands are offered, plus gdsh_lib's `tree` and `utils` when installed.
- Either way, commands from `bridge.json` are added.

## Bridge config

The addon reads `~/.mcp-sh/godot/bridge.json`, then `res://.mcp-sh/godot/bridge.json`.
Later files win, and `commandDirs`/`exclude` add up. Use Project > Tools > Restart mcp-sh-godot
Bridge after editing them.

```json
{
  "port": 9510,
  "token": "",
  "autostart": true,
  "editorConsole": true,
  "gdshLib": true,
  "commandDirs": ["res://tools/agent"],
  "commands": {"bake": "res://tools/bake_command.gd"},
  "exclude": ["settings"],
  "include": ["echo"]
}
```

- `commandDirs` are gdsh command folders. `commands` maps a name to one command script.
  Relative paths are relative to the config file, and `~/` is the home folder.
- `exclude` hides commands. The defaults hide gdsh's session builtins, the text tools the
  shell already has (`grep`, `head`, `tail`) and `os`/`term`. `include` brings a default back.
- With a token, set the same one for the shell: `MCP_SH_GODOT_TOKEN`. A different port needs
  `MCP_SH_GODOT_PORT`. The editor also reads both variables as defaults, if it was started
  with them.

Shell overrides go in `~/.mcp-sh/godot/config.json` (or `./.mcp-sh/godot.json` for one
project). See the mcp-sh README for the config keys.

## Development

```sh
make           # host build -> build/<os>-<arch>/mcp-sh-godot
make test
make package   # release archives for every platform
```

The addon's source is `addon/mcp_sh_godot/`, embedded into the binary. To work on it, symlink
that folder into a project's `addons/`.

The makefile body, installers, workflows and `cliff.toml` are rendered from
[sh-templates](https://github.com/brohd11/sh-templates) by the workspace's `render-go.sh`.
Only the config blocks above `# ---- end config ----` are edited here. Pushing a `v*` tag
releases.
