# Custom commands

[Back to README](../README.md)

Commands are gdsh scripts. In the editor, the addon and Editor Console read
`~/.mcp-sh/godot/commands/` and `res://.mcp-sh/godot/commands/` without any config, then the
folders in `commandDirs` (see [Configuration](configuration.md)). A game's bridge
reads these only if its code calls `add_commands_to(host, true)`.

A command is `name.gd` or `name/name.gd`, with subcommands in folders beside it
(`tools/tools.gd`, `tools/bake/bake.gd` for `tools bake`). mcp-sh ignores `.gd` files, so these
folders don't clash with its script commands.

```sh
mcp_sh_godot gdsh new hello               # ~/.mcp-sh/godot/commands/hello/hello.gd
mcp_sh_godot gdsh new tools bake          # tools/bake/bake.gd, plus a tools/tools.gd parent
mcp_sh_godot gdsh new hello --project     # <project>/.mcp-sh/godot/commands/
mcp_sh_godot gdsh new hello --dir ~/my-lib
mcp_sh_godot gdsh add ~/my-lib            # a library folder, into bridge.json commandDirs
mcp_sh_godot gdsh dirs                    # what the bridge reads, in order
```

Folders outside `res://`, and `res://.mcp-sh/`, reload on every request. New commands
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
