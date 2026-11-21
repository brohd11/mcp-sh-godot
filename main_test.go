package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/brohd11/mcp-sh/profile"
)

func load(t *testing.T) *profile.Loaded {
	t.Helper()
	l, err := profile.Load(profile.App{Name: "godot", FS: appFS}, profile.Options{ConfigDir: t.TempDir(), ProjectDir: t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}
	return l
}

func TestConfigLoads(t *testing.T) {
	l := load(t)
	if l.Profile.Title == "" || l.Profile.Setup == "" {
		t.Error("missing title or setup")
	}
	if _, err := l.Sources("test"); err != nil {
		t.Errorf("sources: %v", err)
	}
}

func TestEnvExpansion(t *testing.T) {
	t.Setenv("MCP_SH_GODOT_PORT", "")
	t.Setenv("MCP_SH_GODOT_TOKEN", "")
	if h := load(t).Profile.Host; h.Address != "127.0.0.1:9510" || h.Token != "" {
		t.Fatalf("defaults: %+v", h)
	}
	t.Setenv("MCP_SH_GODOT_PORT", "9600")
	t.Setenv("MCP_SH_GODOT_TOKEN", "s3cret")
	l := load(t)
	if h := l.Profile.Host; h.Address != "127.0.0.1:9600" || h.Token != "s3cret" {
		t.Fatalf("env: %+v", h)
	}
	// Raw keeps the reference, so `config show` never prints the secret.
	if l.Raw.Host.Token != "${MCP_SH_GODOT_TOKEN}" {
		t.Fatalf("raw: %q", l.Raw.Host.Token)
	}
}

func TestProjectFoundFromSubfolder(t *testing.T) {
	game := t.TempDir()
	os.WriteFile(filepath.Join(game, "project.godot"), nil, 0o644)
	scenes := filepath.Join(game, "scenes", "enemies")
	os.MkdirAll(scenes, 0o755)
	o := profile.Options{ConfigDir: t.TempDir(), ProjectMarkers: projectMarkers}
	if got, found := profile.FindProject(scenes, o); got != game || !found {
		t.Fatalf("got %s %v, want %s", got, found, game)
	}
}
