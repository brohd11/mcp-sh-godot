// godot-shell: a sandboxed bash shell over Godot, served over MCP.
// See `godot-shell --help` and the README.
package main

import (
	"embed"

	"github.com/brohd11/agent-shell"
)

// appFS is the built-in config layer.
//
//go:embed config.json
var appFS embed.FS

// version is set at build time via -ldflags "-X main.version=...". See the Makefile.
var version = "dev"

func main() {
	agentshell.Main(agentshell.Config{
		Name:        "godot-shell",
		App:         "godot",
		Version:     version,
		UpdateRepo:  "brohd11/godot-shell",
		FS:          appFS,
		Subcommands: []agentshell.Subcommand{addonCommand(version)},
	})
}
