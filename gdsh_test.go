package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// gdshEnv points the user layer at a temp folder and runs from a temp working folder.
func gdshEnv(t *testing.T) (user string) {
	t.Helper()
	user = filepath.Join(t.TempDir(), "cfg")
	t.Setenv("MCP_SH_CONFIG_DIR", user)
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

func TestGdshNew(t *testing.T) {
	user := gdshEnv(t)
	commands := filepath.Join(user, "commands")

	out, errOut, code := gdsh(t, "new", "hello")
	if code != 0 {
		t.Fatalf("new: %d %s", code, errOut)
	}
	hello := filepath.Join(commands, "hello", "hello.gd")
	src := read(t, hello)
	for _, want := range []string{
		`extends "res://addons/_lib/gdsh/src/core/command_base.gd"`,
		`return "hello"`, "Usage: hello [ARG...]", `&"positional_count": "min:0"`, "func _execute(ctx:Context):",
	} {
		if !strings.Contains(src, want) {
			t.Errorf("command missing %q:\n%s", want, src)
		}
	}
	// The user commands folder is read without config, so there is no `gdsh add` hint.
	if !strings.Contains(out, "Created "+hello) || strings.Contains(out, "gdsh add") || !strings.Contains(out, "hello --help") {
		t.Errorf("new output: %q", out)
	}

	if _, errOut, code = gdsh(t, "new", "hello"); code != 1 || !strings.Contains(errOut, "--force") {
		t.Errorf("existing command: %d %q", code, errOut)
	}
	os.WriteFile(hello, []byte("edited"), 0o644)
	if _, _, code = gdsh(t, "new", "hello", "--force"); code != 0 || read(t, hello) == "edited" {
		t.Errorf("--force: %d", code)
	}

	for _, args := range [][]string{{"new"}, {"new", "a", "--bogus"}, {"new", "a", "--dir"}, {"new", "a", "--project", "--dir", "x"}} {
		if _, _, code = gdsh(t, args...); code != 2 {
			t.Errorf("%v: code %d, want usage 2", args, code)
		}
	}
	if _, errOut, code = gdsh(t, "new", "bad/name"); code != 1 || !strings.Contains(errOut, "invalid command name") {
		t.Errorf("bad name: %d %q", code, errOut)
	}
}

func TestGdshNewSubcommands(t *testing.T) {
	commands := filepath.Join(gdshEnv(t), "commands")

	if _, errOut, code := gdsh(t, "new", "tools", "bake"); code != 0 {
		t.Fatalf("new tools bake: %d %s", code, errOut)
	}
	parent := filepath.Join(commands, "tools", "tools.gd")
	if src := read(t, parent); !strings.Contains(src, `return "tools"`) || !strings.Contains(src, "Usage: tools <subcommand>") || strings.Contains(src, "_execute") {
		t.Errorf("parent:\n%s", src)
	}
	if src := read(t, filepath.Join(commands, "tools", "bake", "bake.gd")); !strings.Contains(src, `return "bake"`) || !strings.Contains(src, "Usage: tools bake [ARG...]") {
		t.Errorf("subcommand:\n%s", src)
	}

	// An existing parent is kept, even without --force.
	os.WriteFile(parent, []byte("mine"), 0o644)
	if out, errOut, code := gdsh(t, "new", "tools", "paint"); code != 0 || read(t, parent) != "mine" || strings.Contains(out, parent) {
		t.Errorf("second subcommand: %d %q %q", code, out, errOut)
	}

	// A single-file command can't take subcommands until it has its own folder.
	os.WriteFile(filepath.Join(commands, "loose.gd"), nil, 0o644)
	if _, errOut, code := gdsh(t, "new", "loose", "sub"); code != 1 || !strings.Contains(errOut, "single-file command") {
		t.Errorf("loose parent: %d %q", code, errOut)
	}
	if _, err := os.Stat(filepath.Join(commands, "loose")); err == nil {
		t.Error("a refused new left files behind")
	}
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
	if _, err := os.Stat(filepath.Join(project, ".mcp-sh", "godot", "commands", "x", "x.gd")); err != nil {
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
	if !strings.Contains(out, "mcp-sh-godot gdsh add "+lib) {
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
	if len(lines) != 3 || !strings.Contains(lines[0], "user commands folder") || !strings.Contains(lines[0], "(missing)") ||
		!strings.Contains(lines[1], "commandDirs: ~/kept") || !strings.HasPrefix(lines[2], lib+"  [") || strings.Contains(lines[2], "missing") {
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
	if !strings.Contains(out, "project commandDirs: res://tools") || !strings.Contains(out, "project commands folder") {
		t.Errorf("dirs in project:\n%s", out)
	}
	if _, errOut, code = gdsh(t, "remove", "res://tools", "--project"); code != 0 {
		t.Errorf("remove res:// entry: %d %s", code, errOut)
	}
}
