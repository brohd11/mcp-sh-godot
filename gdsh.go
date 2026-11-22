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
// from folders: gdsh's shared ~/.gdsh and res://.gdsh roots, then each config layer's folder as
// a root, then bridge.json's commandDirs. A root holds commands/ and packages/<name>/cmd. This
// subcommand writes commands from templates and edits commandDirs and gdshRoot.

//go:embed templates/*.gd.tmpl
var gdshTemplates embed.FS

const (
	gdshUsage   = "gdsh new|search|install|packages|update|uninstall|add|remove|dirs|target ...  (gdsh --help)"
	gdshSummary = "Write and install gdsh commands for the editor bridge, and manage the folders it reads them from"
	gdshHelp    = `usage:
  mcp_sh_godot gdsh new NAME [SUB...] [--project | --dir DIR] [--force]
      Write a command script. Name it as it is typed: 'gdsh new tools bake' writes
      tools/bake/bake.gd, the 'bake' subcommand of 'tools', and a tools/tools.gd parent if
      there is none. It goes in the commands/ folder of the root 'gdsh target' picks, or of
      this project's root (--project), or in any folder (--dir). --force replaces the command.
  mcp_sh_godot gdsh search [TERM] [--refresh]
      List the reviewed command packages (godot-gdsh-lib-manifest), with what they need and
      whether they are installed.
  mcp_sh_godot gdsh install NAME... [--project | --dir ROOT] [--force] [--refresh]
      Install packages and the packages they need into the root's packages/ folder, at the
      versions the index pins. --force reinstalls current ones.
  mcp_sh_godot gdsh packages [--project | --dir ROOT]
      List installed packages, and newer pinned versions.
  mcp_sh_godot gdsh update [NAME...] [--project | --dir ROOT]
      Update the named packages, or every outdated one.
  mcp_sh_godot gdsh uninstall NAME [--project | --dir ROOT] [--force]
      Remove a package; --force even when an installed package needs it.
  mcp_sh_godot gdsh target [mcp-sh|gdsh]
      Show or set the root 'gdsh new' and 'gdsh install' use (gdshRoot in
      ~/.mcp-sh/godot/bridge.json):
        mcp-sh  ~/.mcp-sh/godot, --project: .mcp-sh/godot (default).
                Only the MCP bridge reads it.
        gdsh    ~/.gdsh ($GDSH_HOME), --project: .gdsh.
                Editor Console reads it too.
  mcp_sh_godot gdsh add DIR [--project]
  mcp_sh_godot gdsh remove DIR [--project]
      Add or remove a folder of commands (a library) in bridge.json's commandDirs: the user
      file, or this project's (--project).
  mcp_sh_godot gdsh dirs
      List the folders the bridge reads, in order (later ones win on a name clash).

The bridge reads these command roots without config: ~/.gdsh, res://.gdsh, ~/.mcp-sh/godot
and res://.mcp-sh/godot. Each gives its commands/ folder and every packages/<name>/cmd.
commandDirs come after their layer's root. Folders outside res:// and in res://.gdsh or
res://.mcp-sh are read on every request, so a new command is there without restarting the
bridge, and edits apply on the next run.
Commands extend "res://addons/_lib/gdsh/src/core/command_base.gd"; the bridge swaps that for
the gdsh copy it runs, so the same file works with the addon, Editor Console or the library.
`
	gdshCommandsDir = "commands"
	gdshPackagesDir = "packages"
	bridgeFileName  = "bridge.json"

	targetKey     = "gdshRoot"
	targetMcpSh   = "mcp-sh"
	targetGdsh    = "gdsh"
	targetDefault = targetMcpSh
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

// gdshHome is gdsh's shared user root: $GDSH_HOME, else ~/.gdsh ("" without a home folder),
// as GDSh.Load.home_dir.
func gdshHome() string {
	if dir := os.Getenv("GDSH_HOME"); dir != "" {
		return dir
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".gdsh")
}

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
	case "target":
		err = gdshTarget(args[1:], stdout)
	case "search", "install", "packages", "update", "uninstall":
		err = gdshPackages(args[0], args[1:], stdout)
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
	if dir != "" {
		abs, err := filepath.Abs(profile.ResolveDir(dir, "."))
		if err != nil {
			return err
		}
		folder = abs
	} else {
		target, err := readTarget()
		if err != nil {
			return err
		}
		projectRoot := ""
		if project {
			if projectRoot, err = findProject(""); err != nil {
				return err
			}
		}
		if folder = targetFolder(target, projectRoot); folder == "" {
			return errors.New("no home folder for ~/.gdsh: set GDSH_HOME or use --dir")
		}
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

// gdshFolders lists the folders the bridge reads, in its order: the ~/.gdsh and project .gdsh
// roots, then per layer (user, then project when run inside one) its root and commandDirs.
func gdshFolders() []gdshFolder {
	project, perr := findProject("")
	var out []gdshFolder
	if home := gdshHome(); home != "" {
		out = append(out, rootFolders(home, "gdsh user")...)
	}
	layers := []gdshLayer{userLayer()}
	if perr == nil {
		out = append(out, rootFolders(filepath.Join(project, ".gdsh"), "gdsh project")...)
		layers = append(layers, projectLayer(project))
	}
	for _, l := range layers {
		out = append(out, rootFolders(l.dir, l.label)...)
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

// rootFolders is GDSh.Load.root_dirs: commands/ (listed even when missing, as where new
// commands go), then each packages/<name>/cmd that exists, sorted.
func rootFolders(root, label string) []gdshFolder {
	out := []gdshFolder{{filepath.Join(root, gdshCommandsDir), label + " commands folder"}}
	entries, err := os.ReadDir(filepath.Join(root, gdshPackagesDir))
	if err != nil {
		return out
	}
	for _, e := range entries { // ReadDir sorts by name
		cmd := filepath.Join(root, gdshPackagesDir, e.Name(), "cmd")
		if e.IsDir() && dirExists(cmd) {
			out = append(out, gdshFolder{cmd, label + " package " + e.Name()})
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
		return gdshHome()
	case project != "":
		return projectLayer(project).dir
	}
	return userLayer().dir
}

// targetFolder is where 'gdsh new' writes for a target: its root's commands/.
func targetFolder(target, project string) string {
	if root := targetRoot(target, project); root != "" {
		return filepath.Join(root, gdshCommandsDir)
	}
	return ""
}

func gdshTarget(args []string, stdout io.Writer) error {
	if len(args) > 1 {
		return usageError("target takes at most one value")
	}
	path := userLayer().bridgeFile()
	if len(args) == 0 {
		target, err := readTarget()
		if err != nil {
			return err
		}
		fmt.Fprintf(stdout, "%s: 'gdsh new' writes to %s and 'gdsh install' to %s (--project: <project>/%s)\n", target,
			targetFolder(target, ""), filepath.Join(targetRoot(target, ""), gdshPackagesDir), filepath.ToSlash(targetRoot(target, ".")))
		return nil
	}
	target := args[0]
	if target != targetMcpSh && target != targetGdsh {
		return usageError(fmt.Sprintf("target is %q or %q, not %q", targetMcpSh, targetGdsh, target))
	}
	cfg, err := readBridgeConfig(path)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	cfg.raw[targetKey], _ = json.Marshal(target)
	if err := cfg.write(path); err != nil {
		return err
	}
	fmt.Fprintf(stdout, "Set %s to %s in %s: 'gdsh new' writes to %s and 'gdsh install' to %s\n",
		targetKey, target, path, targetFolder(target, ""), filepath.Join(targetRoot(target, ""), gdshPackagesDir))
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
