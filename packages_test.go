package main

import (
	"archive/zip"
	"bytes"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	gdshpkg "github.com/brohd11/gdsh-pkg"
)

func pkgZip(t *testing.T, name, version string, require ...string) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	files := map[string]string{
		"package.cfg":                      "[package]\nversion=\"" + version + "\"\npath=\"addons/_lib/gdsh_lib/" + name + "\"\nrequire=[\"" + strings.Join(require, `","`) + "\"]\n",
		"cmd/manifest.gd":                  "extends RefCounted\n",
		"cmd/" + name + "/" + name + ".gd": "# command\n",
	}
	for p, body := range files {
		w, _ := zw.Create("repo-sha/" + p)
		w.Write([]byte(body))
	}
	zw.Close()
	return buf.Bytes()
}

// fakeIndex points pkgClient at a server with level, terrain3d (needs level) and utils
// (project only).
func fakeIndex(t *testing.T) {
	t.Helper()
	index := `{"version": 1, "packages": [
  {"name": "level", "repo": "o/level", "summary": "Level building", "tags": ["3d"], "tag": "v0.1.0", "commit": "c1", "requires": []},
  {"name": "terrain3d", "repo": "o/terrain3d", "summary": "Terrain tools", "tags": ["3d"], "tag": "v0.1.0", "commit": "c2", "requires": ["o/level"]},
  {"name": "utils", "repo": "o/utils", "summary": "cat, ls", "tag": "v0.4.0", "commit": "c3", "requires": [], "project_only": ["o/util-r"]}
]}`
	zips := map[string][]byte{
		"/o/level/c1.zip":     pkgZip(t, "level", "0.1.0"),
		"/o/terrain3d/c2.zip": pkgZip(t, "terrain3d", "0.1.0", "o/level@v0.1.0"),
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/manifest.json" {
			w.Write([]byte(index))
		} else if z, ok := zips[r.URL.Path]; ok {
			w.Write(z)
		} else {
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	saved := pkgClient
	pkgClient = &gdshpkg.Client{
		ManifestURL: srv.URL + "/manifest.json",
		ArchiveURL:  func(repo, commit string) string { return srv.URL + "/" + repo + "/" + commit + ".zip" },
		CacheDir:    t.TempDir(),
	}
	t.Cleanup(func() { pkgClient = saved })
}

func TestGdshPackages(t *testing.T) {
	gdshEnv(t)
	fakeIndex(t)
	packages := filepath.Join(os.Getenv("GDSH_HOME"), "packages")

	out, errOut, code := gdsh(t, "search", "3d")
	if code != 0 || !strings.Contains(out, "terrain3d") || !strings.Contains(out, "needs level") || strings.Contains(out, "utils") {
		t.Fatalf("search: %d %q %q", code, out, errOut)
	}
	if out, _, _ = gdsh(t, "search"); !strings.Contains(out, "project only: gdaddon install o/utils") {
		t.Errorf("search all: %q", out)
	}

	out, errOut, code = gdsh(t, "install", "terrain3d")
	if code != 0 || !strings.Contains(out, "level is needed by terrain3d") || !strings.Contains(out, "Installed terrain3d v0.1.0") ||
		!strings.Contains(out, "lists them on its next request") {
		t.Fatalf("install: %d %q %q", code, out, errOut)
	}
	for _, p := range []string{"level/cmd/level/level.gd", "terrain3d/package.cfg"} {
		if _, err := os.Stat(filepath.Join(packages, p)); err != nil {
			t.Error(err)
		}
	}
	if out, _, _ = gdsh(t, "install", "level"); !strings.Contains(out, "level 0.1.0 is already installed") {
		t.Errorf("reinstall: %q", out)
	}
	if out, _, _ = gdsh(t, "packages"); !strings.Contains(out, "level") || !strings.Contains(out, "terrain3d") || strings.Contains(out, "update:") {
		t.Errorf("packages: %q", out)
	}
	if out, _, _ = gdsh(t, "update"); !strings.Contains(out, "pinned version") {
		t.Errorf("update with nothing outdated: %q", out)
	}

	// An older level shows as outdated and updates.
	os.WriteFile(filepath.Join(packages, "level", "package.cfg"), []byte("[package]\nversion=\"0.0.9\"\npath=\"x/level\"\n"), 0o644)
	if out, _, _ = gdsh(t, "packages"); !strings.Contains(out, "(update: v0.1.0)") {
		t.Errorf("outdated: %q", out)
	}
	if out, _, _ = gdsh(t, "update"); !strings.Contains(out, "Updated level v0.1.0") {
		t.Errorf("update: %q", out)
	}

	if _, errOut, code = gdsh(t, "uninstall", "level"); code != 1 || !strings.Contains(errOut, "needed by terrain3d") {
		t.Errorf("uninstall a dependency: %d %q", code, errOut)
	}
	if out, _, code = gdsh(t, "uninstall", "terrain3d"); code != 0 || !strings.Contains(out, "Removed terrain3d") {
		t.Errorf("uninstall: %d %q", code, out)
	}
	if _, errOut, code = gdsh(t, "install", "utils"); code != 1 || !strings.Contains(errOut, "gdaddon install o/utils") {
		t.Errorf("project-only: %d %q", code, errOut)
	}
	for _, args := range [][]string{{"install"}, {"uninstall"}, {"packages", "x"}, {"install", "level", "--bogus"}, {"install", "x", "--project", "--dir", "y"}} {
		if _, _, code = gdsh(t, args...); code != 2 {
			t.Errorf("%v: code %d, want usage 2", args, code)
		}
	}
}

func TestGdshPackagesRoots(t *testing.T) {
	gdshEnv(t)
	fakeIndex(t)
	home := os.Getenv("GDSH_HOME")

	// The default target is gdsh.
	if _, errOut, code := gdsh(t, "install", "level"); code != 0 {
		t.Fatalf("install into ~/.gdsh: %s", errOut)
	}
	if _, err := os.Stat(filepath.Join(home, "packages", "level", "package.cfg")); err != nil {
		t.Error(err)
	}

	project := newProject(t)
	t.Chdir(project)
	if _, errOut, code := gdsh(t, "install", "level", "--project"); code != 0 {
		t.Fatalf("install --project: %s", errOut)
	}
	if _, err := os.Stat(filepath.Join(project, ".gdsh", "packages", "level")); err != nil {
		t.Error(err)
	}

	gdsh(t, "target", "mcp-sh")
	if _, errOut, code := gdsh(t, "install", "level", "--project"); code != 0 {
		t.Fatalf("install --project with mcp-sh target: %s", errOut)
	}
	if _, err := os.Stat(filepath.Join(project, ".mcp-sh", "godot", "packages", "level")); err != nil {
		t.Error(err)
	}

	// A root the bridge doesn't read gets the hint instead.
	out, _, code := gdsh(t, "install", "level", "--dir", "elsewhere")
	if code != 0 || !strings.Contains(out, "doesn't read") {
		t.Errorf("--dir: %d %q", code, out)
	}
}
