package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"path/filepath"
	"strings"
	"time"

	gdshpkg "github.com/brohd11/gdsh-pkg"
	"github.com/brohd11/mcp-sh/profile"
)

// pkgClient fetches the package index and archives; tests point it at a fake server.
var pkgClient = &gdshpkg.Client{}

type pkgArgs struct {
	names            []string
	project, force   bool
	refresh          bool
	dir              string
	allowForce       bool
	allowRefresh     bool
	allowRoot        bool
	maxNames, minNum int
}

func parsePkgArgs(sub string, args []string, a pkgArgs) (pkgArgs, error) {
	for i := 0; i < len(args); i++ {
		arg := args[i]
		switch {
		case arg == "--project" && a.allowRoot:
			a.project = true
		case arg == "--force" && a.allowForce:
			a.force = true
		case arg == "--refresh" && a.allowRefresh:
			a.refresh = true
		case arg == "--dir" && a.allowRoot:
			if i+1 >= len(args) {
				return a, usageError("--dir needs a root folder")
			}
			i++
			a.dir = args[i]
		case strings.HasPrefix(arg, "--dir=") && a.allowRoot:
			a.dir = strings.TrimPrefix(arg, "--dir=")
		case strings.HasPrefix(arg, "-"):
			return a, usageError(fmt.Sprintf("%s: unknown flag %q", sub, arg))
		default:
			a.names = append(a.names, arg)
		}
	}
	switch {
	case a.project && a.dir != "":
		return a, usageError("use --project or --dir, not both")
	case len(a.names) < a.minNum:
		return a, usageError(sub + " needs a package name")
	case a.maxNames >= 0 && len(a.names) > a.maxNames:
		return a, usageError(fmt.Sprintf("%s takes at most %d name(s)", sub, a.maxNames))
	}
	return a, nil
}

// pkgRoot is the root a package command works on: --dir, else the target's user or project root.
func pkgRoot(a pkgArgs) (string, error) {
	if a.dir != "" {
		return filepath.Abs(profile.ResolveDir(a.dir, "."))
	}
	target, err := readTarget()
	if err != nil {
		return "", err
	}
	project := ""
	if a.project {
		if project, err = findProject(""); err != nil {
			return "", err
		}
	}
	root := targetRoot(target, project)
	if root == "" {
		return "", errors.New("no home folder for ~/.gdsh: set GDSH_HOME or use --dir")
	}
	return root, nil
}

// rootRead reports whether the bridge reads root's packages: it is one of its command roots.
func rootRead(root string) bool {
	roots := []string{gdshHome(), userLayer().dir}
	if project, err := findProject(""); err == nil {
		roots = append(roots, filepath.Join(project, ".gdsh"), projectLayer(project).dir)
	}
	for _, r := range roots {
		if r != "" && sameDir(r, root) {
			return true
		}
	}
	return false
}

func gdshPackages(sub string, args []string, stdout io.Writer) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	switch sub {
	case "search":
		a, err := parsePkgArgs(sub, args, pkgArgs{allowRefresh: true, maxNames: 1})
		if err != nil {
			return err
		}
		return pkgSearch(ctx, a, stdout)
	case "install":
		a, err := parsePkgArgs(sub, args, pkgArgs{allowRoot: true, allowForce: true, allowRefresh: true, maxNames: -1, minNum: 1})
		if err != nil {
			return err
		}
		return pkgInstall(ctx, a, stdout)
	case "packages":
		a, err := parsePkgArgs(sub, args, pkgArgs{allowRoot: true})
		if err != nil {
			return err
		}
		return pkgList(ctx, a, stdout)
	case "update":
		a, err := parsePkgArgs(sub, args, pkgArgs{allowRoot: true, allowRefresh: true, maxNames: -1})
		if err != nil {
			return err
		}
		return pkgUpdate(ctx, a, stdout)
	case "uninstall":
		a, err := parsePkgArgs(sub, args, pkgArgs{allowRoot: true, allowForce: true, maxNames: 1, minNum: 1})
		if err != nil {
			return err
		}
		return pkgUninstall(ctx, a, stdout)
	}
	return usageError("unknown gdsh command " + sub)
}

func fetchIndex(ctx context.Context, refresh bool, stdout io.Writer) (*gdshpkg.Index, error) {
	idx, err := pkgClient.FetchIndex(ctx, refresh)
	if err != nil {
		return nil, err
	}
	if idx.Stale {
		fmt.Fprintf(stdout, "(offline: using the package index cached %s)\n", idx.Fetched.Format("2006-01-02 15:04"))
	}
	return idx, nil
}

func installedVersions(root string) map[string]string {
	have := map[string]string{}
	if list, err := gdshpkg.ListInstalled(root); err == nil {
		for _, in := range list {
			have[in.Name] = in.Cfg.Version
		}
	}
	return have
}

func pkgSearch(ctx context.Context, a pkgArgs, stdout io.Writer) error {
	idx, err := fetchIndex(ctx, a.refresh, stdout)
	if err != nil {
		return err
	}
	term := ""
	if len(a.names) == 1 {
		term = a.names[0]
	}
	root, err := pkgRoot(a)
	if err != nil {
		return err
	}
	have := installedVersions(root)
	found := idx.Search(term)
	if len(found) == 0 {
		fmt.Fprintf(stdout, "No packages match %q.\n", term)
		return nil
	}
	for _, p := range found {
		fmt.Fprintf(stdout, "%-12s %-8s %s\n", p.Name, p.Tag, p.Summary)
		var notes []string
		if len(p.Requires) > 0 {
			var names []string
			for _, r := range p.Requires {
				if dep, ok := idx.Find(r); ok {
					names = append(names, dep.Name)
				}
			}
			notes = append(notes, "needs "+strings.Join(names, ", "))
		}
		if v, ok := have[p.Name]; ok {
			notes = append(notes, "installed "+v)
		}
		if len(p.ProjectOnly) > 0 {
			notes = append(notes, "project only: gdaddon install "+p.Repo)
		}
		if len(notes) > 0 {
			fmt.Fprintf(stdout, "%-12s %-8s (%s)\n", "", "", strings.Join(notes, "; "))
		}
	}
	fmt.Fprintf(stdout, "\nInstall with: mcp_sh_godot gdsh install NAME  (into %s)\n", gdshpkg.PackagesDir(root))
	return nil
}

func pkgInstall(ctx context.Context, a pkgArgs, stdout io.Writer) error {
	root, err := pkgRoot(a)
	if err != nil {
		return err
	}
	idx, err := fetchIndex(ctx, a.refresh, stdout)
	if err != nil {
		return err
	}
	steps, err := idx.Plan(root, a.names, a.force)
	if err != nil {
		return err
	}
	return runSteps(ctx, root, steps, stdout)
}

func runSteps(ctx context.Context, root string, steps []gdshpkg.Step, stdout io.Writer) error {
	changed := false
	for _, s := range steps {
		if s.Action == gdshpkg.ActKeep {
			fmt.Fprintf(stdout, "%s %s is already installed\n", s.Pkg.Name, s.Installed)
			continue
		}
		changed = true
		if s.For != "" {
			fmt.Fprintf(stdout, "%s is needed by %s\n", s.Pkg.Name, s.For)
		}
	}
	if !changed {
		return nil
	}
	err := pkgClient.Install(ctx, root, steps, func(line string) { fmt.Fprintln(stdout, line) })
	if err != nil {
		return err
	}
	fmt.Fprintf(stdout, "Packages are in %s.\n", gdshpkg.PackagesDir(root))
	if rootRead(root) {
		fmt.Fprintln(stdout, "The bridge lists them on its next request; try '<command> --help' through mcp_sh_godot.")
	} else {
		fmt.Fprintf(stdout, "The bridge doesn't read %s. Add each package's cmd/ folder with: mcp_sh_godot gdsh add DIR\n", root)
	}
	return nil
}

func pkgList(ctx context.Context, a pkgArgs, stdout io.Writer) error {
	root, err := pkgRoot(a)
	if err != nil {
		return err
	}
	installed, err := gdshpkg.ListInstalled(root)
	if err != nil {
		return err
	}
	if len(installed) == 0 {
		fmt.Fprintf(stdout, "No packages in %s. Find some with: mcp_sh_godot gdsh search\n", gdshpkg.PackagesDir(root))
		return nil
	}
	idx, idxErr := pkgClient.FetchIndex(ctx, false)
	updates := map[string]string{}
	if idxErr == nil {
		for _, u := range idx.Outdated(installed) {
			updates[u.Name] = u.Pkg.Tag
		}
	}
	fmt.Fprintf(stdout, "%s:\n", gdshpkg.PackagesDir(root))
	for _, in := range installed {
		note := ""
		switch {
		case updates[in.Name] != "":
			note = "  (update: " + updates[in.Name] + ")"
		case idxErr == nil:
			if _, ok := idx.Find(in.Name); !ok {
				note = "  (not in the index)"
			}
		}
		fmt.Fprintf(stdout, "  %-12s %s%s\n", in.Name, in.Cfg.Version, note)
	}
	if idxErr != nil {
		fmt.Fprintf(stdout, "(updates unknown: %v)\n", idxErr)
	} else if len(updates) > 0 {
		fmt.Fprintln(stdout, "Update with: mcp_sh_godot gdsh update")
	}
	return nil
}

func pkgUpdate(ctx context.Context, a pkgArgs, stdout io.Writer) error {
	root, err := pkgRoot(a)
	if err != nil {
		return err
	}
	idx, err := fetchIndex(ctx, a.refresh, stdout)
	if err != nil {
		return err
	}
	names := a.names
	if len(names) == 0 {
		installed, err := gdshpkg.ListInstalled(root)
		if err != nil {
			return err
		}
		for _, u := range idx.Outdated(installed) {
			names = append(names, u.Name)
		}
		if len(names) == 0 {
			fmt.Fprintln(stdout, "Every package is at its pinned version.")
			return nil
		}
	} else {
		have := installedVersions(root)
		for _, n := range names {
			if _, ok := have[n]; !ok {
				return fmt.Errorf("%s is not installed in %s (install it with: mcp_sh_godot gdsh install %s)", n, root, n)
			}
		}
	}
	steps, err := idx.Plan(root, names, false)
	if err != nil {
		return err
	}
	return runSteps(ctx, root, steps, stdout)
}

func pkgUninstall(ctx context.Context, a pkgArgs, stdout io.Writer) error {
	root, err := pkgRoot(a)
	if err != nil {
		return err
	}
	name := a.names[0]
	installed, err := gdshpkg.ListInstalled(root)
	if err != nil {
		return err
	}
	var m *gdshpkg.Manifest
	if idx, err := pkgClient.FetchIndex(ctx, false); err == nil {
		m = idx.Manifest
	}
	if deps := gdshpkg.Dependents(installed, name, m); len(deps) > 0 && !a.force {
		return fmt.Errorf("%s is needed by %s; uninstall that first, or use --force", name, strings.Join(deps, ", "))
	}
	if err := gdshpkg.Remove(root, name); err != nil {
		return err
	}
	fmt.Fprintf(stdout, "Removed %s from %s\n", name, gdshpkg.PackagesDir(root))
	return nil
}
