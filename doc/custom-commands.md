# Custom commands

[Back to README](../README.md)

Commands are gdsh scripts. In the editor, the addon and Editor Console's `mcp --start` read
these command roots without any config, in this order:

| Root | Also read by the Editor Console prompt |
| --- | --- |
| `~/.gdsh/` (`$GDSH_HOME`), then `res://.gdsh/` | yes |
| `~/.mcp-sh/godot/`, then its `commandDirs` | no |
| `res://.mcp-sh/godot/`, then its `commandDirs` | no |

Each root holds `commands/` (loose commands) and `packages/<name>/cmd` (command packages, such
as a cloned gdsh_lib package). Later folders win on a name clash. See
[Configuration](configuration.md) for `commandDirs`. A game's bridge reads the roots only if
its code calls `add_commands_to(host, true)`.

A command is `name.gd` or `name/name.gd`, with subcommands in folders beside it
(`tools/tools.gd`, `tools/bake/bake.gd` for `tools bake`). mcp-sh ignores `.gd` files, so these
folders don't clash with its script commands.

```sh
mcp_sh_godot gdsh target gdsh             # once: new commands go to ~/.gdsh (default: mcp-sh)
mcp_sh_godot gdsh new hello               # <user commands folder>/hello/hello.gd
mcp_sh_godot gdsh new tools bake          # tools/bake/bake.gd, plus a tools/tools.gd parent
mcp_sh_godot gdsh new hello --project     # <project>/.gdsh/commands/ or .mcp-sh/godot/commands/
mcp_sh_godot gdsh new hello --dir ~/my-lib
mcp_sh_godot gdsh add ~/my-lib            # a library folder, into bridge.json commandDirs
mcp_sh_godot gdsh dirs                    # what the bridge reads, in order
```

`gdsh target` stores `gdshRoot` (`mcp-sh` or `gdsh`) in `~/.mcp-sh/godot/bridge.json`. It
picks where `gdsh new` and `gdsh install` write. Pick `gdsh` if you also use Editor Console,
so its prompt has the same commands. Keep `mcp-sh` if you only use the agent.

## Command packages

Reviewed packages are listed in
[godot-gdsh-lib-manifest](https://github.com/brohd11/godot-gdsh-lib-manifest). Each one is
pinned to a reviewed commit, and installs download exactly that commit:

```sh
mcp_sh_godot gdsh search                 # what's available, what each needs
mcp_sh_godot gdsh install terrain3d      # and level, which it needs, beside it
mcp_sh_godot gdsh packages               # installed, with newer pinned versions
mcp_sh_godot gdsh update                 # every outdated package
mcp_sh_godot gdsh uninstall terrain3d
```

- Packages go in `<root>/packages/<name>`, and the bridge lists them on its next request.
  `--project` uses the project's root and `--dir ROOT` any root.
- A package that needs non-gdsh code (gdsh_lib utils needs util_r) can't live in a root.
  Install it into the project with `gdaddon install` instead.
- `GDSH_PACKAGE_INDEX` points at another index, as a URL or a local `manifest.json`.

Folders outside `res://`, and the `res://.gdsh/` and `res://.mcp-sh/` roots, reload on every
request. New commands
and edits apply without restarting. Failed commands remain listed; invoking one
reports its file, line and parse error on Godot 4.5+ (older versions refer to the
Output panel). Requests also report subcommands that failed to load.

Commands extend `res://addons/_lib/gdsh/src/core/command_base.gd`. The bridge rewrites
this path to its active gdsh copy, so a script works with the addon, Editor Console
or the library. Each command:
- extends `command_base.gd` directly, not a base of your own;
- reaches the library through the constants it inherits (`Context`, `Options`, `Utils`,
  `Paths`, `ExitCode`), not its own preloads;
- doesn't override `_init`;
- declares `&"positional_count"` (for example `"min:0"`) if it takes arguments, since the
  default is none.
