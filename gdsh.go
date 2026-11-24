package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"

	gdshpkg "github.com/brohd11/gdsh-pkg"
	"github.com/brohd11/godot-gdsh-cli/gdshcmd"
	"github.com/brohd11/mcp-sh"
	"github.com/brohd11/mcp-sh/profile"
)

// gdsh commands are GDScript files the editor bridge (the addon's, or Editor Console's) loads
// from folders: gdsh's shared ~/.gdsh and res://.gdsh roots, then each config layer's folder as
// a root, then bridge.json's commandDirs. The verbs shared with the gdsh CLI come from gdshcmd;
// this file adds the bridge's own: target (gdshRoot) and add/remove (commandDirs).

const (
	gdshUsage   = "gdsh new|search|install|packages|update|uninstall|dirs|target|add|remove ...  (gdsh --help)"
	gdshSummary = "Write and install gdsh commands for the editor bridge, and manage the folders it reads them from"
	gdshTail    = `The bridge reads these command roots without config: ~/.gdsh, res://.gdsh, ~/.mcp-sh/godot
and res://.mcp-sh/godot. Each gives its commands/ folder and every packages/<name>/cmd; 'new'
and 'package install' use the user or project root 'target' picks. commandDirs come after their
layer's root. Folders outside res:// and in res://.gdsh or res://.mcp-sh are read on every
request, so a new command is there without restarting the bridge, and edits apply on the next
run.
Commands extend "res://addons/_lib/gdsh/src/core/command_base.gd"; the bridge swaps that for
the gdsh copy it runs, so the same file works with the addon, Editor Console or the gdsh CLI.
`
	bridgeFileName = "bridge.json"

	targetKey     = "gdshRoot"
	targetMcpSh   = "mcp-sh"
	targetGdsh    = "gdsh"
	targetDefault = targetGdsh
)

// pkgClient is the package index client; nil is the published index. Tests swap it.
var pkgClient *gdshpkg.Client

func gdshCommand() mcpsh.Subcommand {
	return mcpsh.Subcommand{
		Name: "gdsh", Usage: gdshUsage, Summary: gdshSummary,
		Run: runGdsh,
	}
}

func runGdsh(args []string, stdout, stderr io.Writer) int {
	return gdshHost().Run(args, stdout, stderr)
}

func gdshHost() *gdshcmd.Host {
	return &gdshcmd.Host{
		Prog: "mcp_sh_godot gdsh", Name: "The bridge", AddCmd: "mcp_sh_godot gdsh add",
		Root: func(project string) (string, error) {
			target, err := readTarget()
			if err != nil {
				return "", err
			}
			return targetRoot(target, project), nil
		},
		Folders: gdshFolders,
		Try:     func(line string) string { return "'" + line + "' through mcp_sh_godot" },
		Listed:  "The bridge lists them on its next request; try '<command> --help' through mcp_sh_godot.",
		Note:    "(A bridge that read its folders only at startup lists a new command after a restart.)",
		Extra: []gdshcmd.Verb{
			{Names: []string{"target"}, Usage: []string{"target [mcp-sh|gdsh]"},
				Help: `      Show or set the root 'new' and 'package install' use (gdshRoot in
      ~/.mcp-sh/godot/bridge.json):
        gdsh    ~/.gdsh ($GDSH_HOME), --project: .gdsh (default).
                Shared with the gdsh CLI and Editor Console.
        mcp-sh  ~/.mcp-sh/godot, --project: .mcp-sh/godot.
                Only the MCP bridge reads it.
`, Run: func(_ string, args []string, stdout io.Writer) error { return gdshTarget(args, stdout) }},
			{Names: []string{"add", "remove"}, Usage: []string{"add DIR [--project]", "remove DIR [--project]"},
				Help: `      Add or remove a folder of commands (a library) in bridge.json's commandDirs: the user
      file, or this project's (--project).
`, Run: gdshEditDirs},
		},
		HelpTail: gdshTail,
		Client:   pkgClient,
	}
}

// gdshLayer is one config layer's folder: ~/.mcp-sh/godot, or <project>/.mcp-sh/godot.
type gdshLayer struct {
	label   string
	dir     string // holds bridge.json and commands/
	project string // the project folder, for res:// entries; "" for the user layer
}

func (l gdshLayer) commandsDir() string { return filepath.Join(l.dir, gdshcmd.CommandsDir) }
func (l gdshLayer) bridgeFile() string  { return filepath.Join(l.dir, bridgeFileName) }

func userLayer() gdshLayer {
	return gdshLayer{label: "user", dir: filepath.Join(profile.ConfigDir(), "godot")}
}

func projectLayer(project string) gdshLayer {
	return gdshLayer{label: "project", dir: filepath.Join(project, ".mcp-sh", "godot"), project: project}
}

// gdshFolders lists the folders the bridge reads, in its order: the ~/.gdsh and project .gdsh
// roots, then per layer (user, then project when run inside one) its root and commandDirs.
func gdshFolders() []gdshcmd.Folder {
	out := gdshcmd.GdshFolders()
	layers := []gdshLayer{userLayer()}
	if project, err := findProject(""); err == nil {
		layers = append(layers, projectLayer(project))
	}
	for _, l := range layers {
		out = append(out, gdshcmd.RootFolders(l.dir, l.label)...)
		cfg, err := readBridgeConfig(l.bridgeFile())
		if err != nil {
			continue
		}
		for _, d := range cfg.dirs {
			out = append(out, gdshcmd.Folder{Path: l.resolve(d), Source: l.label + " commandDirs: " + d})
		}
	}
	return out
}

// resolve is bridge_config.gd's _resolve: res:// is the project, ~/ the home folder, and other
// relative entries are relative to the config file's folder.
func (l gdshLayer) resolve(entry string) string {
	switch {
	case strings.HasPrefix(entry, "res://"):
		if l.project == "" {
			return entry
		}
		return filepath.Join(l.project, filepath.FromSlash(strings.TrimPrefix(entry, "res://")))
	case entry == "~" || strings.HasPrefix(entry, "~/"):
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, entry[1:])
		}
		return entry
	case filepath.IsAbs(entry):
		return filepath.Clean(entry)
	}
	return filepath.Join(l.dir, entry)
}

func gdshEditDirs(sub string, args []string, stdout io.Writer) error {
	layer := userLayer()
	var dir string
	for _, a := range args {
		switch {
		case a == "--project":
			root, err := findProject("")
			if err != nil {
				return err
			}
			layer = projectLayer(root)
		case strings.HasPrefix(a, "-") || dir != "":
			return gdshcmd.UsageError(fmt.Sprintf("unexpected argument %q", a))
		default:
			dir = a
		}
	}
	if dir == "" {
		return gdshcmd.UsageError(sub + " needs a folder")
	}
	entry := layer.entryFor(dir)
	path := layer.bridgeFile()
	cfg, err := readBridgeConfig(path)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	if sub == "add" {
		if i := cfg.find(layer, dir, entry); i >= 0 {
			return fmt.Errorf("%s is already in %s", cfg.dirs[i], path)
		}
		cfg.dirs = append(cfg.dirs, entry)
		if !dirExists(layer.resolve(entry)) {
			fmt.Fprintf(stdout, "Note: %s doesn't exist yet.\n", layer.resolve(entry))
		}
	} else {
		i := cfg.find(layer, dir, entry)
		if i < 0 {
			if len(cfg.dirs) == 0 {
				return fmt.Errorf("no commandDirs in %s", path)
			}
			return fmt.Errorf("%s is not in %s (commandDirs: %s)", dir, path, strings.Join(cfg.dirs, ", "))
		}
		entry = cfg.dirs[i]
		cfg.dirs = slices.Delete(cfg.dirs, i, i+1)
	}
	if err := cfg.write(path); err != nil {
		return err
	}
	verb, prep := "Added", "to"
	if sub == "remove" {
		verb, prep = "Removed", "from"
	}
	fmt.Fprintf(stdout, "%s %s %s commandDirs in %s\n", verb, entry, prep, path)
	fmt.Fprintln(stdout, "Restart the bridge to apply it (Project > Tools > Restart mcp-sh-godot Bridge, or 'mcp --stop; mcp --start' in Editor Console).")
	return nil
}

// readTarget is gdshRoot from the user bridge.json, or the default.
func readTarget() (string, error) {
	cfg, err := readBridgeConfig(userLayer().bridgeFile())
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return "", err
	}
	raw, ok := cfg.raw[targetKey]
	if !ok {
		return targetDefault, nil
	}
	var target string
	if err := json.Unmarshal(raw, &target); err != nil || (target != targetMcpSh && target != targetGdsh) {
		return "", fmt.Errorf("%s: %s must be %q or %q, not %s", userLayer().bridgeFile(), targetKey, targetMcpSh, targetGdsh, raw)
	}
	return target, nil
}

// targetRoot is the command root a target picks: the user one, or with a project folder that
// project's. "" when ~/.gdsh has no home folder.
func targetRoot(target, project string) string {
	switch {
	case target == targetGdsh && project != "":
		return filepath.Join(project, ".gdsh")
	case target == targetGdsh:
		return gdshcmd.Home()
	case project != "":
		return projectLayer(project).dir
	}
	return userLayer().dir
}

// targetFolder is where 'gdsh new' writes for a target: its root's commands/.
func targetFolder(target, project string) string {
	if root := targetRoot(target, project); root != "" {
		return filepath.Join(root, gdshcmd.CommandsDir)
	}
	return ""
}

func gdshTarget(args []string, stdout io.Writer) error {
	if len(args) > 1 {
		return gdshcmd.UsageError("target takes at most one value")
	}
	path := userLayer().bridgeFile()
	if len(args) == 0 {
		target, err := readTarget()
		if err != nil {
			return err
		}
		fmt.Fprintf(stdout, "%s: 'gdsh new' writes to %s and 'gdsh package install' to %s (--project: <project>/%s)\n", target,
			targetFolder(target, ""), filepath.Join(targetRoot(target, ""), gdshcmd.PackagesDir), filepath.ToSlash(targetRoot(target, ".")))
		return nil
	}
	target := args[0]
	if target != targetMcpSh && target != targetGdsh {
		return gdshcmd.UsageError(fmt.Sprintf("target is %q or %q, not %q", targetMcpSh, targetGdsh, target))
	}
	cfg, err := readBridgeConfig(path)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	cfg.raw[targetKey], _ = json.Marshal(target)
	if err := cfg.write(path); err != nil {
		return err
	}
	fmt.Fprintf(stdout, "Set %s to %s in %s: 'gdsh new' writes to %s and 'gdsh package install' to %s\n",
		targetKey, target, path, targetFolder(target, ""), filepath.Join(targetRoot(target, ""), gdshcmd.PackagesDir))
	return nil
}

// entryFor is how a typed folder is stored: ~ and res:// as typed, a folder inside the project
// as res:// in the project file (so it travels with the project), anything else absolute.
func (l gdshLayer) entryFor(dir string) string {
	if strings.HasPrefix(dir, "~") || strings.HasPrefix(dir, "res://") {
		return dir
	}
	abs, err := filepath.Abs(dir)
	if err != nil {
		return dir
	}
	if l.project != "" {
		if rel, err := filepath.Rel(l.project, abs); err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			return "res://" + filepath.ToSlash(rel)
		}
	}
	return abs
}

// bridgeConfig is a bridge.json, kept whole so editing commandDirs leaves other keys as they were.
type bridgeConfig struct {
	raw  map[string]json.RawMessage
	dirs []string
}

func readBridgeConfig(path string) (*bridgeConfig, error) {
	cfg := &bridgeConfig{raw: map[string]json.RawMessage{}}
	data, err := os.ReadFile(path)
	if err != nil {
		return cfg, err
	}
	if err := json.Unmarshal(data, &cfg.raw); err != nil {
		return cfg, fmt.Errorf("%s: %w", path, err)
	}
	if d, ok := cfg.raw["commandDirs"]; ok {
		if err := json.Unmarshal(d, &cfg.dirs); err != nil {
			return cfg, fmt.Errorf("%s: commandDirs: %w", path, err)
		}
	}
	return cfg, nil
}

// find matches an entry as typed, as it would be stored, or by the folder it names.
func (c *bridgeConfig) find(l gdshLayer, typed, entry string) int {
	target := l.resolve(entry)
	for i, d := range c.dirs {
		if d == typed || d == entry || sameDir(l.resolve(d), target) {
			return i
		}
	}
	return -1
}

func (c *bridgeConfig) write(path string) error {
	if len(c.dirs) == 0 {
		delete(c.raw, "commandDirs")
	} else {
		d, err := json.Marshal(c.dirs)
		if err != nil {
			return err
		}
		c.raw["commandDirs"] = d
	}
	data, err := json.MarshalIndent(c.raw, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, append(data, '\n'), 0o644)
}

func sameDir(a, b string) bool { return gdshcmd.SameDir(a, b) }
