package main

import (
	"testing"

	"github.com/brohd11/agent-shell/profile"
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
	t.Setenv("GODOT_SHELL_PORT", "")
	t.Setenv("GODOT_SHELL_TOKEN", "")
	if h := load(t).Profile.Host; h.Address != "127.0.0.1:9510" || h.Token != "" {
		t.Fatalf("defaults: %+v", h)
	}
	t.Setenv("GODOT_SHELL_PORT", "9600")
	t.Setenv("GODOT_SHELL_TOKEN", "s3cret")
	l := load(t)
	if h := l.Profile.Host; h.Address != "127.0.0.1:9600" || h.Token != "s3cret" {
		t.Fatalf("env: %+v", h)
	}
	// Raw keeps the reference, so `config show` never prints the secret.
	if l.Raw.Host.Token != "${GODOT_SHELL_TOKEN}" {
		t.Fatalf("raw: %q", l.Raw.Host.Token)
	}
}
