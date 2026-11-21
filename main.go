// mcp-sh-godot: a sandboxed bash shell over Godot, served over MCP.
// See `mcp_sh_godot --help` and the README.
package main

import (
	"embed"

	"github.com/brohd11/mcp-sh"
	"github.com/brohd11/mcp-sh/profile"
)

// appFS is the built-in config layer.
//
//go:embed config.json
var appFS embed.FS

// projectMarkers find the project from deeper inside it, as Godot does: the folder holding
// project.godot is res://, and with file access on, the shell's "/".
var projectMarkers = []string{"project.godot"}

// version is set at build time via -ldflags "-X main.version=...". See the Makefile.
var version = "dev"

func main() {
	mcpsh.Main(mcpsh.Config{
		Name:        "mcp_sh_godot",
		App:         "godot",
		Version:     version,
		UpdateRepo:  "brohd11/mcp-sh-godot",
		FS:          appFS,
		Options:     profile.Options{ProjectMarkers: projectMarkers},
		Subcommands: []mcpsh.Subcommand{addonCommand(version), gdshCommand()},
		// A running game serves its own bridge on 9511 (bridge.gd RUNTIME_PORT).
		Registrations: []mcpsh.Registration{{
			Suffix: "_game",
			Env:    map[string]string{"MCP_SH_GODOT_PORT": "9511"},
			Label:  "running game",
		}},
	})
}
