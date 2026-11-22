package main

import (
	"bytes"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func newProject(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "project.godot"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}

func addon(t *testing.T, version string, args ...string) (string, string, int) {
	t.Helper()
	var out, errOut bytes.Buffer
	code := runAddon(version, args, &out, &errOut)
	return out.String(), errOut.String(), code
}

func TestAddonInstall(t *testing.T) {
	project := newProject(t)
	sub := filepath.Join(project, "scenes")
	os.Mkdir(sub, 0o755)
	embedded := embeddedVersion()

	// Found from a subfolder, like running in the shell anywhere inside the project.
	out, errOut, code := addon(t, "v9.9.9", "install", sub)
	if code != 0 {
		t.Fatalf("install: %d %s", code, errOut)
	}
	if !strings.Contains(out, "plugin "+embedded) || !strings.Contains(out, "Enable \"mcp-sh-godot\"") || strings.Contains(out, "Editor Console") {
		t.Fatalf("install output: %q", out)
	}
	dest := filepath.Join(project, addonDir)
	for _, f := range []string{"plugin.gd", "plugin.cfg", "src/host.gd"} {
		if _, err := os.Stat(filepath.Join(dest, f)); err != nil {
			t.Fatal(err)
		}
	}
	// The binary's version never reaches plugin.cfg: the plugin carries its own.
	if name, v, _ := readPluginCfg(dest); name != addonName || v != embedded {
		t.Fatalf("plugin.cfg: %q %q, want %q", name, v, embedded)
	}

	// Files of an older version go; Godot's .uid files of kept scripts stay.
	os.WriteFile(filepath.Join(dest, "old.gd"), nil, 0o644)
	os.WriteFile(filepath.Join(dest, "old.gd.uid"), nil, 0o644)
	os.WriteFile(filepath.Join(dest, "plugin.gd.uid"), []byte("uid://x"), 0o644)
	if _, _, code = addon(t, "v9.9.9", "install", project); code != 0 {
		t.Fatalf("reinstall: %d", code)
	}
	for f, want := range map[string]bool{"old.gd": false, "old.gd.uid": false, "plugin.gd.uid": true} {
		if _, err := os.Stat(filepath.Join(dest, f)); (err == nil) != want {
			t.Errorf("%s exists=%v, want %v", f, err == nil, want)
		}
	}

	// A newer installed addon needs --force; an unversioned one never blocks.
	cfg := filepath.Join(dest, "plugin.cfg")
	os.WriteFile(cfg, []byte("[plugin]\nname=\"mcp-sh-godot\"\nversion=\"99.0.0\"\n"), 0o644)
	if _, errOut, code := addon(t, "v1", "install", project); code != 1 || !strings.Contains(errOut, "newer than the one this binary carries") {
		t.Fatalf("downgrade: %d %q", code, errOut)
	}
	if _, _, code := addon(t, "v1", "install", project, "--force"); code != 0 {
		t.Fatal("forced downgrade failed")
	}
	os.WriteFile(cfg, []byte("[plugin]\nname=\"mcp-sh-godot\"\nversion=\"dev\"\n"), 0o644)
	if _, _, code := addon(t, "v1", "install", project); code != 0 {
		t.Fatal("dev addon blocked the install")
	}
}

// The embedded addon is a release export: the libraries it needs are bundled under src/remote.
func TestEmbeddedAddonIsSelfContained(t *testing.T) {
	for _, lib := range []string{"gdsh", "mcp_sh_bridge", "gdsh_lib/editor", "gdsh_lib/tree", "gdsh_lib/utils"} {
		if _, err := fs.Stat(addonFS, addonSrc+"/src/remote/addons/_lib/"+lib); err != nil {
			t.Errorf("embedded addon lacks %s: %v", lib, err)
		}
	}
	if v := embeddedVersion(); v == "unknown" || v == "" {
		t.Errorf("embedded plugin.cfg has no version")
	}
}

func TestAddonInstallEditorConsoleNote(t *testing.T) {
	project := newProject(t)
	os.MkdirAll(filepath.Join(project, consoleDir), 0o755)
	if out, _, _ := addon(t, "v1.0.0", "install", project); !strings.Contains(out, "mcp --start") {
		t.Fatalf("editor_console note: %q", out)
	}
}

func TestAddonForeignDir(t *testing.T) {
	project := newProject(t)
	dest := filepath.Join(project, addonDir)
	os.MkdirAll(dest, 0o755)
	os.WriteFile(filepath.Join(dest, "plugin.cfg"), []byte("[plugin]\nname=\"other\"\nversion=\"9.9.9\"\n"), 0o644)
	if _, errOut, code := addon(t, "v1.0.0", "install", project); code != 1 || !strings.Contains(errOut, "not the mcp-sh-godot plugin") {
		t.Fatalf("install over foreign: %d %q", code, errOut)
	}
	if _, errOut, code := addon(t, "v1.0.0", "remove", project); code != 1 || !strings.Contains(errOut, "not removing") {
		t.Fatalf("remove foreign: %d %q", code, errOut)
	}
}

func TestAddonStatusAndRemove(t *testing.T) {
	project := newProject(t)
	embedded := embeddedVersion()
	if out, _, _ := addon(t, "v1.0.0", "status", project); !strings.Contains(out, "not installed") || !strings.Contains(out, "carries "+embedded) {
		t.Fatalf("status before: %q", out)
	}
	addon(t, "v1.0.0", "install", project)
	out, _, _ := addon(t, "v1.0.0", "status", project)
	if !strings.Contains(out, embedded+" (matches this binary's)") || !strings.Contains(out, "editor_console  not installed") {
		t.Fatalf("status: %q", out)
	}
	os.MkdirAll(filepath.Join(project, consoleDir), 0o755)
	if out, _, _ := addon(t, "v1.0.0", "status", project); !strings.Contains(out, "editor_console  installed") {
		t.Fatalf("status with editor_console: %q", out)
	}
	os.WriteFile(filepath.Join(project, addonDir, "plugin.cfg"), []byte("[plugin]\nname=\"mcp-sh-godot\"\nversion=\"0.0.1\"\n"), 0o644)
	if out, _, _ := addon(t, "v1.0.0", "status", project); !strings.Contains(out, "0.0.1, this binary carries "+embedded) {
		t.Fatalf("status mismatch: %q", out)
	}
	if _, _, code := addon(t, "v1.0.0", "remove", project); code != 0 {
		t.Fatal("remove failed")
	}
	if dirExists(filepath.Join(project, addonDir)) {
		t.Fatal("addon still there")
	}
}

func TestAddonUsage(t *testing.T) {
	if _, _, code := addon(t, "v1", "frobnicate"); code != 2 {
		t.Fatal("bad subcommand accepted")
	}
	if _, errOut, code := addon(t, "v1", "install", t.TempDir()); code != 1 || !strings.Contains(errOut, "no project.godot") {
		t.Fatalf("no project: %d %q", code, errOut)
	}
	if _, _, code := addon(t, "v1", "status", "a", "b"); code != 2 {
		t.Fatal("extra argument accepted")
	}
}
