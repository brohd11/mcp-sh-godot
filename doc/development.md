# Development

[Back to README](../README.md)

```sh
make           # host build -> build/<os>-<arch>/mcp_sh_godot
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
