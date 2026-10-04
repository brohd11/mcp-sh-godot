# godot-shell

A sandboxed bash shell over the live Godot editor, served over MCP. Built on
[agent-shell](https://github.com/brohd11/agent-shell): it talks to the editor_console
addon's bridge (a native agent-shell host on `127.0.0.1:9510`), so the agent runs the
Editor Console's commands with pipes, loops and jq.

```sh
godot-shell run 'tree root | tree nodes --recursive | grep -c Camera'
```

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/brohd11/godot-shell/main/install.sh | sh
godot-shell setup        # ~/.agent-shell/godot/ + `claude mcp add -s user godot-shell -- <path>`
godot-shell commands     # check what the shell can reach
```

On Windows: `irm https://raw.githubusercontent.com/brohd11/godot-shell/main/install.ps1 | iex`.

In the Godot editor, enable the editor_console addon, then run `mcp bridge start` in its
console (or once: `config startup --add "mcp bridge start"`). Set `EDITOR_CONSOLE_PORT` /
`EDITOR_CONSOLE_TOKEN` if the bridge uses another port or a token.

Overrides go in `~/.agent-shell/godot/config.json` (or `./.agent-shell/godot.json` for one
project). See the agent-shell README for the config keys.

## Development

```sh
make           # host build -> build/<os>-<arch>/godot-shell
make test
make package   # release archives for every platform
```

The makefile body, installers, workflows and `cliff.toml` are rendered from
[sh-templates](https://github.com/brohd11/sh-templates) by the workspace's `render-go.sh`.
Only the config blocks above `# ---- end config ----` are edited here. Pushing a `v*` tag
releases.
