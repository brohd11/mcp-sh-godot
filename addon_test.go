package main

import (
	"bytes"
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

	// Found from a subfolder, like running in the shell anywhere inside the project.
	out, errOut, code := addon(t, "v1.2.0", "install", sub)
	if code != 0 {
		t.Fatalf("install: %d %s", code, errOut)
	}
	if !strings.Contains(out, "gdsh is missing") || !strings.Contains(out, "Enable \"mcp-sh-godot\"") {
		t.Fatalf("install output: %q", out)
	}
	dest := filepath.Join(project, addonDir)
	for _, f := range []string{"plugin.gd", "bridge.gd", "runner.gd", "bridge_config.gd"} {
		if _, err := os.Stat(filepath.Join(dest, f)); err != nil {
			t.Fatal(err)
		}
	}
	if name, v, _ := readPluginCfg(dest); name != addonName || v != "v1.2.0" {
		t.Fatalf("plugin.cfg: %q %q", name, v)
	}

	// Files of an older version go; Godot's .uid files of kept scripts stay.
	os.WriteFile(filepath.Join(dest, "old.gd"), nil, 0o644)
	os.WriteFile(filepath.Join(dest, "old.gd.uid"), nil, 0o644)
	os.WriteFile(filepath.Join(dest, "bridge.gd.uid"), []byte("uid://x"), 0o644)
	os.MkdirAll(filepath.Join(project, gdshDir), 0o755)
	out, _, code = addon(t, "v1.3.0", "install", project)
	if code != 0 || strings.Contains(out, "gdsh is missing") {
		t.Fatalf("upgrade: %d %q", code, out)
	}
	for f, want := range map[string]bool{"old.gd": false, "old.gd.uid": false, "bridge.gd.uid": true} {
		if _, err := os.Stat(filepath.Join(dest, f)); (err == nil) != want {
			t.Errorf("%s exists=%v, want %v", f, err == nil, want)
		}
	}

	// A newer installed addon needs --force; a dev binary never blocks.
	if _, errOut, code := addon(t, "v1.2.9", "install", project); code != 1 || !strings.Contains(errOut, "newer than this binary") {
		t.Fatalf("downgrade: %d %q", code, errOut)
	}
	if _, _, code := addon(t, "v1.2.9", "install", project, "--force"); code != 0 {
		t.Fatal("forced downgrade failed")
	}
	if _, _, code := addon(t, "dev", "install", project); code != 0 {
		t.Fatal("dev install blocked")
	}
}

func TestAddonForeignDir(t *testing.T) {
	project := newProject(t)
	dest := filepath.Join(project, addonDir)
	os.MkdirAll(dest, 0o755)
	os.WriteFile(filepath.Join(dest, "plugin.cfg"), []byte("[plugin]\nname=\"other\"\nversion=\"9.9.9\"\n"), 0o644)
	if _, errOut, code := addon(t, "v1.0.0", "install", project); code != 1 || !strings.Contains(errOut, "not the mcp-sh-godot addon") {
		t.Fatalf("install over foreign: %d %q", code, errOut)
	}
	if _, errOut, code := addon(t, "v1.0.0", "remove", project); code != 1 || !strings.Contains(errOut, "not removing") {
		t.Fatalf("remove foreign: %d %q", code, errOut)
	}
}

func TestAddonStatusAndRemove(t *testing.T) {
	project := newProject(t)
	if out, _, _ := addon(t, "v1.0.0", "status", project); !strings.Contains(out, "not installed") {
		t.Fatalf("status before: %q", out)
	}
	addon(t, "v1.0.0", "install", project)
	os.MkdirAll(filepath.Join(project, consoleDir), 0o755)
	out, _, _ := addon(t, "v1.0.0", "status", project)
	if !strings.Contains(out, "v1.0.0 (matches the binary)") || !strings.Contains(out, "gdsh            missing") || !strings.Contains(out, "editor_console  installed") {
		t.Fatalf("status: %q", out)
	}
	if out, _, _ := addon(t, "v1.1.0", "status", project); !strings.Contains(out, "v1.0.0, binary is v1.1.0") {
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
