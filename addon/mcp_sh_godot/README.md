# mcp-sh-godot plugin

The Godot side of [mcp-sh-godot](https://github.com/brohd11/mcp-sh-godot): while enabled, it
serves the editor's commands on `127.0.0.1:9510` to the mcp-sh-godot agent shell. The release
bundles everything it uses, so a project needs nothing else:

- [mcp_sh_bridge](https://github.com/brohd11/godot-mcp-sh-bridge), the listener;
- [gdsh](https://github.com/brohd11/godot-gdsh) and gdsh_lib's `utils`, `tree`, `editor`, `test` and
  `data` commands (`ls`, `cat`, `find`, `tree`, `editor`, `settings`, `resource`, `test`, `data`, ...). `gdtest` is
  `test` under a name the agent shell's own `test` builtin doesn't hide.

Install it with the binary, so the two match, then enable **mcp-sh-godot** in Project Settings >
Plugins:

```sh
mcp_sh_godot plugin install
```

With [Editor Console](https://github.com/brohd11/Godot-Editor-Console) you don't need this
plugin: run `mcp --start` in the console. When the console is running, this plugin stays off.

Settings (port, token, extra command folders) come from `bridge.json`; see the mcp-sh-godot
README. Use Project > Tools > Restart mcp-sh-godot Bridge after editing it.

## Development

This repo is the plugin's source. Its export (`gdpackage export mcp_sh_godot`, or the release
workflow on a `v*` tag) bundles the libraries under `vendor/`. mcp-sh-godot vendors the
released zip with `scripts/fetch_addon.sh`.

```sh
godot --headless --path . --script res://addons/mcp_sh_godot/_export_ignore/test/host_test.gd
```
