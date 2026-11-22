package main

import (
	"embed"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/brohd11/mcp-sh"
)

// addonFS is the editor addon, written into a project by `mcp_sh_godot plugin install`. It is
// the released export of github.com/brohd11/godot-mcp-sh-plugin, which bundles every library it
// uses, vendored by scripts/fetch_addon.sh (`go generate`) and committed.
//
//go:generate sh scripts/fetch_addon.sh
//go:embed all:addon/mcp_sh_godot
var addonFS embed.FS

const (
	addonSrc     = "addon/mcp_sh_godot"
	addonDir     = "addons/mcp_sh_godot" // relative to the project folder
	addonName    = "mcp-sh-godot"        // plugin.cfg name
	consoleDir   = "addons/editor_console"
	addonUsage   = "plugin install|status|remove [PROJECT_DIR] [--force]"
	addonSummary = "Install, check or remove the editor plugin in a Godot project"
)

// embeddedVersion is the version in the embedded addon's plugin.cfg. The plugin is released
// on its own, so this is not the binary's version.
func embeddedVersion() string {
	data, err := addonFS.ReadFile(addonSrc + "/plugin.cfg")
	if err != nil {
		return "unknown"
	}
	if m := cfgVersion.FindSubmatch(data); m != nil {
		return string(m[1])
	}
	return "unknown"
}

func addonCommand(version string) mcpsh.Subcommand {
	return mcpsh.Subcommand{
		Name: "plugin", Usage: addonUsage, Summary: addonSummary,
		Run: func(args []string, stdout, stderr io.Writer) int {
			return runAddon(version, args, stdout, stderr)
		},
	}
}

func runAddon(version string, args []string, stdout, stderr io.Writer) int {
	usage := func() int {
		fmt.Fprintf(stderr, "usage: mcp_sh_godot %s\n", addonUsage)
		return 2
	}
	if len(args) == 0 {
		return usage()
	}
	sub, dir, force := args[0], "", false
	for _, a := range args[1:] {
		switch {
		case a == "--force" && sub == "install":
			force = true
		case strings.HasPrefix(a, "-") || dir != "":
			fmt.Fprintf(stderr, "unexpected argument %q\n", a)
			return usage()
		default:
			dir = a
		}
	}
	if sub != "install" && sub != "status" && sub != "remove" {
		return usage()
	}
	project, err := findProject(dir)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	switch sub {
	case "install":
		err = installAddon(project, embeddedVersion(), force, stdout)
	case "status":
		addonStatus(project, version, embeddedVersion(), stdout)
	case "remove":
		err = removeAddon(project, stdout)
	}
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	return 0
}

// findProject returns the folder holding project.godot: dir (default: the working
// directory) or the nearest parent.
func findProject(dir string) (string, error) {
	if dir == "" {
		dir = "."
	}
	abs, err := filepath.Abs(dir)
	if err != nil {
		return "", err
	}
	for d := abs; ; d = filepath.Dir(d) {
		if _, err := os.Stat(filepath.Join(d, "project.godot")); err == nil {
			return d, nil
		}
		if filepath.Dir(d) == d {
			return "", fmt.Errorf("no project.godot in %s or its parents", abs)
		}
	}
}

func installAddon(project, version string, force bool, stdout io.Writer) error {
	dest := filepath.Join(project, addonDir)
	if name, installed, ok := readPluginCfg(dest); ok || dirExists(dest) {
		switch {
		case !ok || name != addonName:
			if !force {
				return fmt.Errorf("%s exists but is not the mcp-sh-godot plugin; use --force to replace it", dest)
			}
		case compareVersions(installed, version) > 0 && !force:
			return fmt.Errorf("installed plugin %s is newer than the one this binary carries (%s); update mcp_sh_godot, or use --force", installed, version)
		}
	}
	keep := map[string]bool{}
	err := fs.WalkDir(addonFS, addonSrc, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel := strings.TrimPrefix(strings.TrimPrefix(p, addonSrc), "/")
		target := filepath.Join(dest, filepath.FromSlash(rel))
		if d.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		data, err := addonFS.ReadFile(p)
		if err != nil {
			return err
		}
		keep[rel] = true
		return os.WriteFile(target, data, 0o644)
	})
	if err != nil {
		return err
	}
	if err := pruneAddon(dest, keep); err != nil {
		return err
	}
	fmt.Fprintf(stdout, "Installed mcp-sh-godot plugin %s in %s\n", version, dest)
	if dirExists(filepath.Join(project, consoleDir)) {
		fmt.Fprintln(stdout, "Note: Editor Console is installed. It serves its own commands with 'mcp --start', and this plugin stays off while it runs.")
	}
	fmt.Fprintln(stdout, "Enable \"mcp-sh-godot\" in Project Settings > Plugins (an enabled plugin reloads on its own).")
	return nil
}

// pruneAddon deletes files a previous version installed that this one doesn't have.
// Godot's .uid and .import files beside a kept file stay, so their ids don't change.
func pruneAddon(dest string, keep map[string]bool) error {
	return filepath.WalkDir(dest, func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		rel, err := filepath.Rel(dest, p)
		if err != nil {
			return err
		}
		rel = filepath.ToSlash(rel)
		base := strings.TrimSuffix(strings.TrimSuffix(rel, ".uid"), ".import")
		if keep[rel] || keep[base] {
			return nil
		}
		return os.Remove(p)
	})
}

func addonStatus(project, binary, embedded string, stdout io.Writer) {
	fmt.Fprintf(stdout, "project         %s\n", project)
	dest := filepath.Join(project, addonDir)
	switch name, installed, ok := readPluginCfg(dest); {
	case !ok && !dirExists(dest):
		fmt.Fprintf(stdout, "plugin          not installed (this binary, %s, carries %s): mcp_sh_godot plugin install\n", binary, embedded)
	case !ok || name != addonName:
		fmt.Fprintf(stdout, "plugin          res://%s is not the mcp-sh-godot plugin\n", addonDir)
	case installed != embedded:
		fmt.Fprintf(stdout, "plugin          %s, this binary carries %s: mcp_sh_godot plugin install\n", installed, embedded)
	default:
		fmt.Fprintf(stdout, "plugin          %s (matches this binary's)\n", installed)
	}
	if dirExists(filepath.Join(project, consoleDir)) {
		fmt.Fprintln(stdout, "editor_console  installed: serve with its 'mcp --start'; this plugin is not needed and stays off while it runs")
	} else {
		fmt.Fprintln(stdout, "editor_console  not installed: the plugin serves gdsh, the editor commands and bridge.json's")
	}
}

func removeAddon(project string, stdout io.Writer) error {
	dest := filepath.Join(project, addonDir)
	name, _, ok := readPluginCfg(dest)
	if !ok && !dirExists(dest) {
		fmt.Fprintf(stdout, "No plugin in %s\n", dest)
		return nil
	}
	if !ok || name != addonName {
		return fmt.Errorf("%s is not the mcp-sh-godot plugin; not removing it", dest)
	}
	if err := os.RemoveAll(dest); err != nil {
		return err
	}
	fmt.Fprintf(stdout, "Removed %s. Disable \"mcp-sh-godot\" in Project Settings > Plugins if it is still listed.\n", dest)
	return nil
}

var (
	cfgName    = regexp.MustCompile(`(?m)^name="([^"]*)"`)
	cfgVersion = regexp.MustCompile(`(?m)^version="([^"]*)"`)
)

// readPluginCfg reads the name and version of the addon installed in dir.
func readPluginCfg(dir string) (name, version string, ok bool) {
	data, err := os.ReadFile(filepath.Join(dir, "plugin.cfg"))
	if err != nil {
		return "", "", false
	}
	if m := cfgName.FindSubmatch(data); m != nil {
		name = string(m[1])
	}
	if m := cfgVersion.FindSubmatch(data); m != nil {
		version = string(m[1])
	}
	return name, version, true
}

func dirExists(p string) bool {
	info, err := os.Stat(p)
	return err == nil && info.IsDir()
}

// compareVersions compares the vMAJOR.MINOR.PATCH prefix of two versions, such as
// `git describe` output. It returns 0 when either has none ("dev"), so dev builds never
// block an install.
func compareVersions(a, b string) int {
	va, okA := parseVersion(a)
	vb, okB := parseVersion(b)
	if !okA || !okB {
		return 0
	}
	for i := range va {
		if va[i] != vb[i] {
			if va[i] > vb[i] {
				return 1
			}
			return -1
		}
	}
	return 0
}

var semverPrefix = regexp.MustCompile(`^v?(\d+)\.(\d+)\.(\d+)`)

func parseVersion(v string) ([3]int, bool) {
	var out [3]int
	m := semverPrefix.FindStringSubmatch(v)
	if m == nil {
		return out, false
	}
	for i := range out {
		out[i], _ = strconv.Atoi(m[i+1])
	}
	return out, true
}
