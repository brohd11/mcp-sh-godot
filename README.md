# mcp-sh-godot

Give an agent a sandboxed bash shell over the live Godot editor or a running game
through MCP. The MCP exposes few commands to keep the context usage low: `run`, `list_commands` and `help`.
Through `run`, the agent uses [gdsh](https://github.com/brohd11/godot-gdsh) commands with pipes, loops, `jq` and `grep`.

You can also register other MCPs to run as commands. This can be use

Built on [mcp-sh](https://github.com/brohd11/mcp-sh).

## Install

**macOS / Linux (sh)**

```sh
curl -fsSL https://raw.githubusercontent.com/brohd11/mcp-sh-godot/main/install.sh | sh
```

**Windows (PowerShell)**

```powershell
irm https://raw.githubusercontent.com/brohd11/mcp-sh-godot/main/install.ps1 | iex
```

Follow the installer's PATH instructions, then run:

```sh
mcp_sh_godot setup
```

`setup` creates `~/.mcp-sh/godot/` and prints registration commands for Claude Code
and Codex. Run the appropriate printed command for your client; `setup` does not
register the server itself.

In your Godot project folder, install the bundled addon:

```sh
mcp_sh_godot addon install
```

Enable **mcp-sh-godot** in **Project Settings > Plugins**. The addon includes the
bridge, gdsh and the utils, tree and editor commands; no other plugins are required.
If you use **Editor Console**, see the [alternative setup](doc/configuration.md#editor-console-alternative).

## Quickstart

With the Godot editor open, check the connection and inspect the project:

```sh
mcp_sh_godot commands
mcp_sh_godot run 'ls res://'
mcp_sh_godot run 'tree root'
```

In your MCP client, ask the agent to inspect the project and scene tree. Use
`list_commands` to discover commands and `help` for usage. Commands act on the live
project; working directory and node state [persist between calls](doc/configuration.md#command-context).

## Documentation

- [Configuration](doc/configuration.md): bridge settings, Editor Console and addon updates.
- [Running games](doc/running-games.md): add a runtime bridge and register the game server.
- [Custom commands](doc/custom-commands.md): create and load gdsh commands.
- [Development](doc/development.md): builds, tests and addon vendoring.
- [Core configuration](https://github.com/brohd11/mcp-sh/blob/main/doc/configuration.md) and
  [sandbox](https://github.com/brohd11/mcp-sh/blob/main/doc/sandbox.md).
