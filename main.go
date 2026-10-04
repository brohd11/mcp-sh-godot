// mcp-sh-godot: a sandboxed bash shell over Godot, served over MCP.
// See `mcp-sh-godot --help` and the README.
package main

import (
	"embed"

	"github.com/brohd11/mcp-sh"
)

// appFS is the built-in config layer.
//
//go:embed config.json
var appFS embed.FS

// version is set at build time via -ldflags "-X main.version=...". See the Makefile.
var version = "dev"

func main() {
	mcpsh.Main(mcpsh.Config{
		Name:        "mcp-sh-godot",
		App:         "godot",
		Version:     version,
		UpdateRepo:  "brohd11/mcp-sh-godot",
		FS:          appFS,
		Subcommands: []mcpsh.Subcommand{addonCommand(version)},
	})
}
