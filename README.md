# mcp-sh-godot

A sandboxed bash shell over the live Godot editor, or a running game, served over MCP. Built
on [mcp-sh](https://github.com/brohd11/mcp-sh). Godot serves its commands through
[mcp_sh_bridge](https://github.com/brohd11/godot-mcp-sh-bridge), a native mcp-sh host on
`127.0.0.1:9510` in the editor (`9511` in a game). The agent runs
[gdsh](https://github.com/brohd11/godot-gdsh) commands with pipes, loops and jq.

```sh
mcp-sh-godot run 'tree root | tree nodes --recursive | grep -c Camera'
```

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/brohd11/mcp-sh-godot/main/install.sh | sh
mcp-sh-godot setup        # ~/.mcp-sh/godot/ + prints the claude/codex mcp add commands
```

On Windows: `irm https://raw.githubusercontent.com/brohd11/mcp-sh-godot/main/install.ps1 | iex`.

Then, in each Godot project, one of:

- **With [Editor Console](https://github.com/brohd11/Godot-Editor-Console):** you don't need this
  addon. Run `mcp --start` in the console, or add it to the console's startup commands. The
  console requires the bridge package and serves its own commands. They run in the console's
  context (`.gdrc`, the undo stack), taking turns with what you type into it.
- **Without it:** install this binary's addon. It bundles everything it needs (the bridge,
  gdsh, and gdsh_lib's utils, tree and editor commands), so nothing else is installed:

  ```sh
  mcp-sh-godot addon install    # writes res://addons/mcp_sh_godot/
  mcp-sh-godot addon status     # installed vs carried addon version, editor_console
  ```

  Enable **mcp-sh-godot** in Project Settings > Plugins. It listens while the editor is open and
  offers gdsh's commands plus `ls`, `cat`, `find`, `tree`, `editor`, `settings` and `resource`.
  Run `mcp-sh-godot addon install` again after `mcp-sh-godot update`. `addon remove` takes it
  out. If Editor Console is enabled, the addon disables itself.

Either way, commands from `bridge.json` are added. `mcp-sh-godot commands` checks what the shell
can reach.

Commands get their arguments exactly as bash passed them: no gdsh quoting, variables or
aliases apply. `cd` and `pwd` are gdsh's (mcp-sh hands bash's to them), as are `cn` and
`pwn` for the working node. Both carry over between calls, separate from the console prompt.

## In a running game

The bridge is a node from the mcp_sh_bridge package, so a game or app adds it the way the plugin
does. It doesn't need this addon. Then register the `mcp-sh-godot-game` entry that `setup` (and
`--help`) prints for each agent; it sets `MCP_SH_GODOT_PORT=9511`.

```gdscript
const McpShBridge = preload("res://addons/_lib/mcp_sh_bridge/src/bridge.gd")

func _ready():
    var bridge = McpShBridge.new()
    bridge.host = my_console.create_host()  # optional: any GDSh.Host; plain gdsh when null
    add_child(bridge)
```

- It listens on `9511` unless `port` is set, and says `godot runtime` in `list_commands`.
  `port = -1` takes any free port (`get_port()` says which). That suits a game that starts
  its own agent and passes `MCP_SH_GODOT_PORT` to it.
- Release builds don't listen unless `serve_in_release` is set: commands can run any code.
- Without a host it serves gdsh's builtins, which work on the live tree. Use
  `GDSh.Host.new({"command_dirs": ["res://game/commands"]})` for the game's own commands.

## Custom commands

Commands are gdsh scripts. In the editor, the addon and Editor Console read
`~/.mcp-sh/godot/commands/` and `res://.mcp-sh/godot/commands/` without any config, then the
folders in `commandDirs` (see below). A game's own bridge reads none of them unless its code
asks (`add_commands_to(host, true)`). A command is `name.gd` or `name/name.gd`, and its subcommands go in folders beside it
(`tools/tools.gd`, `tools/bake/bake.gd` for `tools bake`). mcp-sh ignores `.gd` files, so these
folders don't clash with its script commands.

```sh
mcp-sh-godot gdsh new hello               # ~/.mcp-sh/godot/commands/hello/hello.gd
mcp-sh-godot gdsh new tools bake          # tools/bake/bake.gd, plus a tools/tools.gd parent
mcp-sh-godot gdsh new hello --project     # <project>/.mcp-sh/godot/commands/
mcp-sh-godot gdsh new hello --dir ~/my-lib
mcp-sh-godot gdsh add ~/my-lib            # a library folder, into bridge.json commandDirs
mcp-sh-godot gdsh dirs                    # what the bridge reads, in order
```

Folders outside `res://`, and those in `res://.mcp-sh/`, are read on every request: a new
command is there without restarting the bridge, and edits apply on the next run. A command
that fails to load is still listed, and running it prints why: the file, line and parse error
on Godot 4.5+ (older versions point to Godot's Output panel). A request whose subcommand failed
to load ends with a note naming it.

Commands extend `"res://addons/_lib/gdsh/src/core/command_base.gd"`. The bridge swaps that
path, when it loads them, for the gdsh copy it runs (the addon's, Editor Console's or the
library's), so one file works with all three. So a command:

- extends `command_base.gd` directly, not a base of your own;
- reaches the library through the constants it inherits (`Context`, `Options`, `Utils`,
  `Paths`, `ExitCode`), not its own preloads;
- doesn't override `_init`;
- declares `&"positional_count"` (for example `"min:0"`) if it takes arguments, since the
  default is none.

## Bridge config

Editor Console and the addon read `~/.mcp-sh/godot/bridge.json`, then
`res://.mcp-sh/godot/bridge.json`. Later files win, and `commandDirs`/`exclude` add up. Each
file's `commands/` folder, beside it, is read before its `commandDirs`. Use
Project > Tools > Restart mcp-sh-godot Bridge (or `mcp --stop; mcp --start` in Editor Console)
after editing them. `autostart` and `gdshLib` are the addon's keys only.

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
  "idleTimeoutMs": 10000
}
```

- `commandDirs` are gdsh command folders. `commands` maps a name to one command script.
  Relative paths are relative to the config file, and `~/` is the home folder.
- `port` 0 is 9510 in the editor; -1 is any free port.
- `maxRequestBytes`, `maxConnections` and `idleTimeoutMs` bound the listener, so a stuck or
  flooding client can't tie up the editor. A longer request line gets a "Request too large"
  error. More connections than the limit, counting those waiting and those being served, are
  closed at once. A connection with no complete request line `idleTimeoutMs` after connecting is
  dropped (running commands aren't timed). The defaults are shown above.
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

The addon is the release export of [godot-mcp-sh-plugin](https://github.com/brohd11/godot-mcp-sh-plugin),
the plugin's own repo, built by gdpackage's release workflow. `addon/mcp_sh_godot/` is that
export, vendored and committed, and embedded into the binary. Don't edit it here. To update it:

```sh
scripts/fetch_addon.sh            # latest plugin release (or: go generate)
scripts/fetch_addon.sh v0.2.0     # a given tag
scripts/fetch_addon.sh --zip FILE # a local export, for testing before a release
```

The listener, its config loader and their tests live in the
[mcp_sh_bridge](https://github.com/brohd11/godot-mcp-sh-bridge) package, and the editor commands in
[gdsh_lib editor](https://github.com/brohd11/godot-gdsh-lib-editor).

The makefile body, installers, workflows and `cliff.toml` are rendered from
[sh-templates](https://github.com/brohd11/sh-templates) by the workspace's `render-go.sh`.
Only the config blocks above `# ---- end config ----` are edited here. Pushing a `v*` tag
releases.
