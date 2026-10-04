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

// addonFS is the editor addon, written into a project by `mcp-sh-godot addon install`, so
// the shell and the bridge it talks to always come from the same tag.
//
//go:embed all:addon/mcp_sh_godot
var addonFS embed.FS

const (
	addonSrc     = "addon/mcp_sh_godot"
	addonDir     = "addons/mcp_sh_godot" // relative to the project folder
	addonName    = "mcp-sh-godot"        // plugin.cfg name
	gdshDir      = "addons/addon_lib/gdsh"
	consoleDir   = "addons/editor_console"
	gdshInstall  = "gdaddon install brohd11/godot-gdsh"
	addonUsage   = "addon install|status|remove [PROJECT_DIR] [--force]"
	addonSummary = "Install, check or remove the editor addon in a Godot project"
)

func addonCommand(version string) mcpsh.Subcommand {
	return mcpsh.Subcommand{
		Name: "addon", Usage: addonUsage, Summary: addonSummary,
		Run: func(args []string, stdout, stderr io.Writer) int {
			return runAddon(version, args, stdout, stderr)
		},
	}
}

func runAddon(version string, args []string, stdout, stderr io.Writer) int {
	usage := func() int {
		fmt.Fprintf(stderr, "usage: mcp-sh-godot %s\n", addonUsage)
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
		err = installAddon(project, version, force, stdout)
	case "status":
		addonStatus(project, version, stdout)
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
				return fmt.Errorf("%s exists but is not the mcp-sh-godot addon; use --force to replace it", dest)
			}
		case compareVersions(installed, version) > 0 && !force:
			return fmt.Errorf("installed addon %s is newer than this binary (%s); update mcp-sh-godot, or use --force", installed, version)
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
		if rel == "plugin.cfg" {
			data = stampVersion(data, version)
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
	fmt.Fprintf(stdout, "Installed mcp-sh-godot addon %s in %s\n", version, dest)
	if !dirExists(filepath.Join(project, gdshDir)) {
		fmt.Fprintf(stdout, "Warning: gdsh is missing (res://%s). The addon needs it: %s\n", gdshDir, gdshInstall)
	}
	fmt.Fprintln(stdout, "Enable \"mcp-sh-godot\" in Project Settings > Plugins (an enabled addon reloads on its own).")
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

func addonStatus(project, version string, stdout io.Writer) {
	fmt.Fprintf(stdout, "project         %s\n", project)
	dest := filepath.Join(project, addonDir)
	switch name, installed, ok := readPluginCfg(dest); {
	case !ok && !dirExists(dest):
		fmt.Fprintln(stdout, "addon           not installed: mcp-sh-godot addon install")
	case !ok || name != addonName:
		fmt.Fprintf(stdout, "addon           res://%s is not the mcp-sh-godot addon\n", addonDir)
	case installed != version:
		fmt.Fprintf(stdout, "addon           %s, binary is %s: mcp-sh-godot addon install\n", installed, version)
	default:
		fmt.Fprintf(stdout, "addon           %s (matches the binary)\n", installed)
	}
	if dirExists(filepath.Join(project, gdshDir)) {
		fmt.Fprintln(stdout, "gdsh            installed")
	} else {
		fmt.Fprintf(stdout, "gdsh            missing: %s\n", gdshInstall)
	}
	if dirExists(filepath.Join(project, consoleDir)) {
		fmt.Fprintln(stdout, "editor_console  installed: its commands are offered while it is enabled")
	} else {
		fmt.Fprintln(stdout, "editor_console  not installed: gdsh and bridge.json commands only")
	}
}

func removeAddon(project string, stdout io.Writer) error {
	dest := filepath.Join(project, addonDir)
	name, _, ok := readPluginCfg(dest)
	if !ok && !dirExists(dest) {
		fmt.Fprintf(stdout, "No addon in %s\n", dest)
		return nil
	}
	if !ok || name != addonName {
		return fmt.Errorf("%s is not the mcp-sh-godot addon; not removing it", dest)
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

func stampVersion(cfg []byte, version string) []byte {
	return cfgVersion.ReplaceAll(cfg, []byte(`version="`+strings.ReplaceAll(version, `"`, ``)+`"`))
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
