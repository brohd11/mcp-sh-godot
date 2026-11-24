package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// gdshEnv points the user layer and ~/.gdsh at temp folders and runs from a temp working folder.
func gdshEnv(t *testing.T) (user string) {
	t.Helper()
	tmp := t.TempDir()
	user = filepath.Join(tmp, "cfg")
	t.Setenv("MCP_SH_CONFIG_DIR", user)
	t.Setenv("GDSH_HOME", filepath.Join(tmp, "gdsh"))
	t.Chdir(t.TempDir())
	return filepath.Join(user, "godot")
}

func gdsh(t *testing.T, args ...string) (string, string, int) {
	t.Helper()
	var out, errOut bytes.Buffer
	code := runGdsh(args, &out, &errOut)
	return out.String(), errOut.String(), code
}

func read(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestGdshNewFolders(t *testing.T) {
	gdshEnv(t)
	if _, errOut, code := gdsh(t, "new", "x", "--project"); code != 1 || !strings.Contains(errOut, "project.godot") {
		t.Errorf("--project outside a project: %d %q", code, errOut)
	}

	project := newProject(t)
	t.Chdir(project)
	if _, errOut, code := gdsh(t, "new", "x", "--project"); code != 0 {
		t.Fatalf("--project: %d %s", code, errOut)
	}
	if _, err := os.Stat(filepath.Join(project, ".gdsh", "commands", "x", "x.gd")); err != nil {
		t.Error(err)
	}

	// A folder the bridge doesn't read yet gets the line that adds it.
	out, errOut, code := gdsh(t, "new", "y", "--dir", "lib")
	if code != 0 {
		t.Fatalf("--dir: %d %s", code, errOut)
	}
	lib, _ := filepath.Abs("lib")
	if _, err := os.Stat(filepath.Join(lib, "y", "y.gd")); err != nil {
		t.Error(err)
	}
	if !strings.Contains(out, "mcp_sh_godot gdsh add "+lib) || !strings.Contains(out, "'y --help' through mcp_sh_godot") {
		t.Errorf("--dir output: %q", out)
	}
	gdsh(t, "add", "lib")
	if out, _, _ = gdsh(t, "new", "z", "--dir=lib"); strings.Contains(out, "gdsh add") {
		t.Errorf("added folder still hinted: %q", out)
	}
}

func TestGdshAddRemove(t *testing.T) {
	user := gdshEnv(t)
	bridge := filepath.Join(user, "bridge.json")
	os.MkdirAll(user, 0o755)
	os.WriteFile(bridge, []byte(`{"port": 9600, "commandDirs": ["~/kept"]}`), 0o644)
	os.Mkdir("lib", 0o755)
	lib, _ := filepath.Abs("lib")

	out, errOut, code := gdsh(t, "add", "lib")
	if code != 0 || !strings.Contains(out, "Added "+lib) || !strings.Contains(out, "Restart the bridge") {
		t.Fatalf("add: %d %q %q", code, out, errOut)
	}
	cfg, err := readBridgeConfig(bridge)
	if err != nil {
		t.Fatal(err)
	}
	if string(cfg.raw["port"]) != "9600" || strings.Join(cfg.dirs, ",") != "~/kept,"+lib {
		t.Errorf("after add: port %s dirs %v", cfg.raw["port"], cfg.dirs)
	}
	if _, errOut, code = gdsh(t, "add", lib); code != 1 || !strings.Contains(errOut, "already in") {
		t.Errorf("duplicate add: %d %q", code, errOut)
	}

	out, _, _ = gdsh(t, "dirs")
	lines := strings.Split(strings.TrimSpace(out), "\n")
	if len(lines) != 4 || !strings.Contains(lines[0], "[gdsh user commands folder]") ||
		!strings.Contains(lines[1], "[user commands folder]") || !strings.Contains(lines[1], "(missing)") ||
		!strings.Contains(lines[2], "commandDirs: ~/kept") || !strings.HasPrefix(lines[3], lib+"  [") || strings.Contains(lines[3], "missing") {
		t.Errorf("dirs:\n%s", out)
	}

	if _, errOut, code = gdsh(t, "remove", "lib"); code != 0 {
		t.Fatalf("remove: %d %s", code, errOut)
	}
	if _, errOut, code = gdsh(t, "remove", "lib"); code != 1 || !strings.Contains(errOut, "is not in") {
		t.Errorf("remove again: %d %q", code, errOut)
	}
	gdsh(t, "remove", "~/kept")
	cfg, _ = readBridgeConfig(bridge)
	if _, ok := cfg.raw["commandDirs"]; ok || string(cfg.raw["port"]) != "9600" {
		t.Errorf("emptied commandDirs should go, port stay: %v", cfg.raw)
	}

	// In the project file, a folder inside the project is stored as res://.
	project := newProject(t)
	t.Chdir(project)
	os.Mkdir("tools", 0o755)
	if _, errOut, code = gdsh(t, "add", "tools", "--project"); code != 0 {
		t.Fatalf("add --project: %d %s", code, errOut)
	}
	cfg, _ = readBridgeConfig(filepath.Join(project, ".mcp-sh", "godot", "bridge.json"))
	if strings.Join(cfg.dirs, ",") != "res://tools" {
		t.Errorf("project entry: %v", cfg.dirs)
	}
	out, _, _ = gdsh(t, "dirs")
	if !strings.Contains(out, "project commandDirs: res://tools") || !strings.Contains(out, "[project commands folder]") ||
		!strings.Contains(out, "[gdsh project commands folder]") {
		t.Errorf("dirs in project:\n%s", out)
	}
	if _, errOut, code = gdsh(t, "remove", "res://tools", "--project"); code != 0 {
		t.Errorf("remove res:// entry: %d %s", code, errOut)
	}
}

func TestGdshTarget(t *testing.T) {
	user := gdshEnv(t)
	home := os.Getenv("GDSH_HOME")
	bridge := filepath.Join(user, "bridge.json")
	os.MkdirAll(user, 0o755)
	os.WriteFile(bridge, []byte(`{"port": 9600}`), 0o644)

	if out, _, code := gdsh(t, "target"); code != 0 || !strings.HasPrefix(out, "gdsh: ") || !strings.Contains(out, filepath.Join(home, "commands")) {
		t.Errorf("default target: %d %q", code, out)
	}
	if _, _, code := gdsh(t, "target", "bogus"); code != 2 {
		t.Errorf("bad target: code %d, want usage 2", code)
	}
	if out, errOut, code := gdsh(t, "target", "mcp-sh"); code != 0 || !strings.Contains(out, filepath.Join(user, "commands")) {
		t.Fatalf("set target: %d %q %q", code, out, errOut)
	}
	cfg, _ := readBridgeConfig(bridge)
	if string(cfg.raw["port"]) != "9600" || string(cfg.raw[targetKey]) != `"mcp-sh"` {
		t.Errorf("target should be stored beside the other keys: %v", cfg.raw)
	}

	// gdsh new follows it, user and --project; a folder the bridge reads needs no `gdsh add`.
	out, errOut, code := gdsh(t, "new", "hi")
	if code != 0 || strings.Contains(out, "gdsh add") {
		t.Fatalf("new with mcp-sh target: %d %q %q", code, out, errOut)
	}
	if _, err := os.Stat(filepath.Join(user, "commands", "hi", "hi.gd")); err != nil {
		t.Error(err)
	}
	project := newProject(t)
	t.Chdir(project)
	if _, errOut, code := gdsh(t, "new", "hi", "--project"); code != 0 {
		t.Fatalf("new --project with mcp-sh target: %d %s", code, errOut)
	}
	if _, err := os.Stat(filepath.Join(project, ".mcp-sh", "godot", "commands", "hi", "hi.gd")); err != nil {
		t.Error(err)
	}

	os.WriteFile(bridge, []byte(`{"gdshRoot": "elsewhere"}`), 0o644)
	if _, errOut, code := gdsh(t, "new", "x"); code != 1 || !strings.Contains(errOut, "gdshRoot must be") {
		t.Errorf("invalid stored target: %d %q", code, errOut)
	}
}

// Each root lists its packages/<name>/cmd after commands/, skipping folders without cmd/.
func TestGdshDirsPackages(t *testing.T) {
	user := gdshEnv(t)
	home := os.Getenv("GDSH_HOME")
	for _, d := range []string{
		filepath.Join(home, "packages", "level", "cmd"),
		filepath.Join(home, "packages", "notes"),
		filepath.Join(user, "packages", "kit", "cmd"),
	} {
		os.MkdirAll(d, 0o755)
	}
	out, _, _ := gdsh(t, "dirs")
	lines := strings.Split(strings.TrimSpace(out), "\n")
	want := []string{"[gdsh user commands folder]", "[gdsh user package level]", "[user commands folder]", "[user package kit]"}
	if len(lines) != len(want) {
		t.Fatalf("dirs:\n%s", out)
	}
	for i, w := range want {
		if !strings.Contains(lines[i], w) {
			t.Errorf("line %d: want %s:\n%s", i, w, out)
		}
	}
}
