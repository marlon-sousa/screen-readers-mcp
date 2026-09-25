// screenreader-mcp domain -- tests for local_socket.go.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
package entities_test

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

func TestLocalSocketPathPrefersTheRuntimeDirectory(t *testing.T) {
	got, err := entities.LocalSocketPath("nvdaMcpBridge", entities.LocalSocketDirs{
		RuntimeDir: "/run/user/1000",
		Home:       "/home/someone",
	})
	if err != nil {
		t.Fatalf("LocalSocketPath: %v", err)
	}
	want := filepath.Join("/run/user/1000", "screenreader-mcp", "nvdaMcpBridge.sock")
	if got != want {
		t.Errorf("path = %q, want %q", got, want)
	}
}

func TestLocalSocketPathFallsBackToTheHomeDirectory(t *testing.T) {
	got, err := entities.LocalSocketPath("voiceoverMcpBridge", entities.LocalSocketDirs{
		Home: "/Users/someone",
	})
	if err != nil {
		t.Fatalf("LocalSocketPath: %v", err)
	}
	want := filepath.Join("/Users/someone", ".screenreader-mcp", "voiceoverMcpBridge.sock")
	if got != want {
		t.Errorf("path = %q, want %q", got, want)
	}
}

func TestLocalSocketPathFailsWhenThereIsNowhereToLook(t *testing.T) {
	_, err := entities.LocalSocketPath("nvdaMcpBridge", entities.LocalSocketDirs{})
	if err == nil {
		t.Fatal("LocalSocketPath succeeded with no runtime directory and no home")
	}
	if !strings.Contains(err.Error(), "XDG_RUNTIME_DIR") {
		t.Errorf("error %q does not name what was missing", err)
	}
}

func TestLocalSocketPathUsesAnAbsolutePathVerbatim(t *testing.T) {
	got, err := entities.LocalSocketPath("/tmp/somewhere/else.sock", entities.LocalSocketDirs{})
	if err != nil {
		t.Fatalf("LocalSocketPath: %v", err)
	}
	if got != "/tmp/somewhere/else.sock" {
		t.Errorf("path = %q, want the override untouched", got)
	}
}

func TestLocalSocketPathRefusesAPathLongerThanSunPath(t *testing.T) {
	name := strings.Repeat("a", entities.MaxLocalSocketPath)

	_, err := entities.LocalSocketPath(name, entities.LocalSocketDirs{RuntimeDir: "/run/user/1000"})

	if err == nil {
		t.Fatal("LocalSocketPath succeeded on a path no unix socket can carry")
	}
	for _, want := range []string{name, "bytes"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error %q does not mention %q", err, want)
		}
	}
}

func TestLocalSocketPathRefusesAnOverlongOverride(t *testing.T) {
	_, err := entities.LocalSocketPath("/tmp/"+strings.Repeat("b", 120)+".sock", entities.LocalSocketDirs{})
	if err == nil {
		t.Fatal("LocalSocketPath accepted an override no unix socket can carry")
	}
}

func TestLocalSocketName(t *testing.T) {
	for _, c := range []struct {
		fileName string
		want     string
		ok       bool
	}{
		{"nvdaMcpBridge.sock", "nvdaMcpBridge", true},
		{"voiceoverMcpBridge.sock", "voiceoverMcpBridge", true},
		{"notes.txt", "", false},
		{"nvdaMcpBridge", "", false},
		{".sock", "", false},
	} {
		t.Run(c.fileName, func(t *testing.T) {
			got, ok := entities.LocalSocketName(c.fileName)
			if ok != c.ok || got != c.want {
				t.Errorf("LocalSocketName(%q) = %q, %v; want %q, %v", c.fileName, got, ok, c.want, c.ok)
			}
		})
	}
}

func TestTheDerivationAndItsInverseAgree(t *testing.T) {
	dirs := entities.LocalSocketDirs{Home: "/Users/someone"}

	path, err := entities.LocalSocketPath("nvdaMcpBridge", dirs)
	if err != nil {
		t.Fatalf("LocalSocketPath: %v", err)
	}
	name, ok := entities.LocalSocketName(filepath.Base(path))

	if !ok || name != "nvdaMcpBridge" {
		t.Errorf("round trip = %q, %v; want the name it started as", name, ok)
	}
}
