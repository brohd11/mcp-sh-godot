package main

import (
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"text/template"

	"github.com/brohd11/mcp-sh"
	"github.com/brohd11/mcp-sh/profile"
)

// gdsh commands are GDScript files the editor bridge (the addon's, or Editor Console's) loads
// from folders: each config layer's commands/ folder, then bridge.json's commandDirs. This
// subcommand writes them from templates and edits commandDirs.

//go:embed templates/*.gd.tmpl
var gdshTemplates embed.FS

const (
	gdshUsage   = "gdsh new|add|remove|dirs ...  (gdsh --help)"
	gdshSummary = "Write gdsh commands for the editor bridge, and manage the folders it reads them from"
	gdshHelp    = `usage:
  mcp_sh_godot gdsh new NAME [SUB...] [--project | --dir DIR] [--force]
      Write a command script. Name it as it is typed: 'gdsh new tools bake' writes
      tools/bake/bake.gd, the 'bake' subcommand of 'tools', and a tools/tools.gd parent if
      there is none. It goes in ~/.mcp-sh/godot/commands, or this project's
      .mcp-sh/godot/commands (--project), or any folder (--dir). --force replaces the command.
  mcp_sh_godot gdsh add DIR [--project]
  mcp_sh_godot gdsh remove DIR [--project]
      Add or remove a folder of commands (a library) in bridge.json's commandDirs: the user
      file, or this project's (--project).
  mcp_sh_godot gdsh dirs
      List the folders the bridge reads, in order (later ones win on a name clash).

The bridge reads ~/.mcp-sh/godot/commands and res://.mcp-sh/godot/commands without config,
then commandDirs. Folders outside res:// and in res://.mcp-sh are read on every request, so a
new command is there without restarting the bridge, and edits apply on the next run.
Commands extend "res://addons/_lib/gdsh/src/core/command_base.gd"; the bridge swaps that for
the gdsh copy it runs, so the same file works with the addon, Editor Console or the library.
`
	gdshCommandsDir = "commands"
	bridgeFileName  = "bridge.json"
)

var gdshName = regexp.MustCompile(`^[A-Za-z0-9_-]+$`)

func gdshCommand() mcpsh.Subcommand {
	return mcpsh.Subcommand{
		Name: "gdsh", Usage: gdshUsage, Summary: gdshSummary,
		Run: func(args []string, stdout, stderr io.Writer) int {
			return runGdsh(args, stdout, stderr)
		},
	}
}

// gdshLayer is one config layer's folder: ~/.mcp-sh/godot, or <project>/.mcp-sh/godot.
type gdshLayer struct {
	label   string
	dir     string // holds bridge.json and commands/
	project string // the project folder, for res:// entries; "" for the user layer
}

func (l gdshLayer) commandsDir() string { return filepath.Join(l.dir, gdshCommandsDir) }
func (l gdshLayer) bridgeFile() string  { return filepath.Join(l.dir, bridgeFileName) }

func userLayer() gdshLayer {
	return gdshLayer{label: "user", dir: filepath.Join(profile.ConfigDir(), "godot")}
}

func projectLayer(project string) gdshLayer {
	return gdshLayer{label: "project", dir: filepath.Join(project, ".mcp-sh", "godot"), project: project}
}

func runGdsh(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprint(stderr, gdshHelp)
		return 2
	}
	if args[0] == "-h" || args[0] == "--help" || args[0] == "help" {
		fmt.Fprint(stdout, gdshHelp)
		return 0
	}
	var err error
	switch args[0] {
	case "new":
		err = gdshNew(args[1:], stdout)
	case "add", "remove":
		err = gdshEditDirs(args[0], args[1:], stdout)
	case "dirs":
		if len(args) > 1 {
			err = usageError("dirs takes no arguments")
		} else {
			gdshDirs(stdout)
		}
	default:
		err = usageError(fmt.Sprintf("unknown gdsh command %q", args[0]))
	}
	var ue usageError
	if errors.As(err, &ue) {
		fmt.Fprintf(stderr, "%s\n\n%s", ue, gdshHelp)
		return 2
	}
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	return 0
}

type usageError string

func (e usageError) Error() string { return string(e) }

// gdshNew writes NAME [SUB...]: missing parents get the parent template, the last name the
// command template.
func gdshNew(args []string, stdout io.Writer) error {
	var names []string
	var dir string
	project, force := false, false
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "--project":
			project = true
		case a == "--force":
			force = true
		case a == "--dir":
			if i+1 >= len(args) {
				return usageError("--dir needs a folder")
			}
			i++
			dir = args[i]
		case strings.HasPrefix(a, "--dir="):
			dir = strings.TrimPrefix(a, "--dir=")
		case strings.HasPrefix(a, "-"):
			return usageError(fmt.Sprintf("unknown flag %q", a))
		default:
			if !gdshName.MatchString(a) {
				return fmt.Errorf("invalid command name %q: use letters, digits, _ and -", a)
			}
			names = append(names, a)
		}
	}
	if len(names) == 0 {
		return usageError("new needs a command name")
	}
	if project && dir != "" {
		return usageError("use --project or --dir, not both")
	}

	var folder string
	switch {
	case dir != "":
		abs, err := filepath.Abs(profile.ResolveDir(dir, "."))
		if err != nil {
			return err
		}
		folder = abs
	case project:
		root, err := findProject("")
		if err != nil {
			return err
		}
		folder = projectLayer(root).commandsDir()
	default:
		folder = userLayer().commandsDir()
	}

	// Plan every file before writing any, so a refusal leaves nothing half made.
	type file struct{ path, tmpl, name, usage string }
	var files []file
	parent := folder
	for i, name := range names {
		usage := strings.Join(names[:i+1], " ")
		if loose := filepath.Join(parent, name+".gd"); fileExists(loose) {
			return fmt.Errorf("%s is a single-file command; move it to %s to give it subcommands or replace it",
				loose, filepath.Join(parent, name, name+".gd"))
		}
		path := filepath.Join(parent, name, name+".gd")
		last := i == len(names)-1
		switch {
		case last && fileExists(path) && !force:
			return fmt.Errorf("%s exists; use --force to replace it", path)
		case last:
			files = append(files, file{path, "command.gd.tmpl", name, usage})
		case !fileExists(path):
			files = append(files, file{path, "parent.gd.tmpl", name, usage})
		}
		parent = filepath.Join(parent, name)
	}
	for _, f := range files {
		if err := writeTemplate(f.path, f.tmpl, f.name, f.usage); err != nil {
			return err
		}
		fmt.Fprintf(stdout, "Created %s\n", f.path)
	}

	if !gdshFolderRead(folder) {
		fmt.Fprintf(stdout, "The bridge doesn't read %s yet. Add it with: mcp_sh_godot gdsh add %s\n", folder, folder)
	}
	fmt.Fprintf(stdout, "Fill in its help and _execute, then check it through mcp_sh_godot: %s --help\n", strings.Join(names, " "))
	fmt.Fprintln(stdout, "(A bridge that read its folders only at startup lists a new command after a restart.)")
	return nil
}

func writeTemplate(path, name, command, usage string) error {
	t, err := template.ParseFS(gdshTemplates, "templates/"+name)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	err = t.Execute(f, map[string]string{"Name": command, "Usage": usage})
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	return err
}

// gdshFolderRead reports whether the bridge reads folder, as a commands/ folder or a
// commandDirs entry, from wherever this runs.
func gdshFolderRead(folder string) bool {
	for _, d := range gdshFolders() {
		if sameDir(d.path, folder) {
			return true
		}
	}
	return false
}

type gdshFolder struct {
	path, source string
}

// gdshFolders lists the folders the bridge reads, in its order: the user layer's commands/
// then its commandDirs, then the project layer's (when run inside a project).
func gdshFolders() []gdshFolder {
	layers := []gdshLayer{userLayer()}
	if root, err := findProject(""); err == nil {
		layers = append(layers, projectLayer(root))
	}
	var out []gdshFolder
	for _, l := range layers {
		out = append(out, gdshFolder{l.commandsDir(), l.label + " commands folder"})
		cfg, err := readBridgeConfig(l.bridgeFile())
		if err != nil {
			continue
		}
		for _, d := range cfg.dirs {
			out = append(out, gdshFolder{l.resolve(d), l.label + " commandDirs: " + d})
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

func gdshDirs(stdout io.Writer) {
	for _, d := range gdshFolders() {
		state := ""
		if !dirExists(d.path) {
			state = "  (missing)"
		}
		fmt.Fprintf(stdout, "%s  [%s]%s\n", d.path, d.source, state)
	}
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
			return usageError(fmt.Sprintf("unexpected argument %q", a))
		default:
			dir = a
		}
	}
	if dir == "" {
		return usageError(sub + " needs a folder")
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

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

func sameDir(a, b string) bool {
	if filepath.Clean(a) == filepath.Clean(b) {
		return true
	}
	ia, errA := os.Stat(a)
	ib, errB := os.Stat(b)
	return errA == nil && errB == nil && os.SameFile(ia, ib)
}
