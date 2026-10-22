package main

import (
	"bytes"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestBridgeListener runs testdata/bridge_test.gd against the embedded addon in a headless
// Godot. It needs an engine: set GODOT to a Godot 4.4+ binary, or it is skipped.
func TestBridgeListener(t *testing.T) {
	godot := os.Getenv("GODOT")
	if godot == "" {
		t.Skip("set GODOT to a Godot binary to run the bridge tests")
	}
	project := t.TempDir()
	if err := os.WriteFile(filepath.Join(project, "project.godot"), []byte("config_version=5\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := installAddon(project, "v0.0.0-test", false, io.Discard); err != nil {
		t.Fatal(err)
	}
	script, err := os.ReadFile(filepath.Join("testdata", "bridge_test.gd"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(project, "bridge_test.gd"), script, 0o644); err != nil {
		t.Fatal(err)
	}

	cmd := exec.Command(godot, "--headless", "--path", project, "-s", "res://bridge_test.gd")
	cmd.Env = append(os.Environ(), "MCP_SH_CONFIG_DIR="+t.TempDir())
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err = <-done:
	case <-time.After(2 * time.Minute):
		_ = cmd.Process.Kill()
		t.Fatalf("bridge tests hung:\n%s", out.String())
	}

	passed := 0
	for _, line := range strings.Split(out.String(), "\n") {
		switch {
		case strings.HasPrefix(line, "ok "):
			passed++
		case strings.HasPrefix(line, "FAIL "):
			t.Error(line)
		}
	}
	if strings.Contains(out.String(), "SCRIPT ERROR") {
		t.Error("script errors in the bridge or the test script")
	}
	if err != nil || passed == 0 {
		t.Fatalf("godot exited with %v after %d passing tests:\n%s", err, passed, out.String())
	}
}
