// screenreader-mcp domain -- tests for local_socket.go.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// These run on EVERY host, which is the point of the derivation being pure: the
// POSIX leaf that calls it is not compiled on Windows at all, so without this
// file the rendezvous rule would be untested on the leg of CI that gates the
// merge. The environment is passed in, so there is nothing to set and nothing
// to restore.
package entities_test

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// $XDG_RUNTIME_DIR first, because on the hosts that set it (systemd Linux) it is
// already per-user, mode 0700 and cleaned at logout -- exactly what decision 4
// asks for, provided.
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

// macOS sets XDG_RUNTIME_DIR for nobody, so this is the branch that is actually
// taken on the host lane 3 is built on.
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

// With neither, there is nowhere to look and saying so is the only honest
// answer -- inventing a relative path would put a socket in whatever directory
// the MCP host happened to launch the server from.
func TestLocalSocketPathFailsWhenThereIsNowhereToLook(t *testing.T) {
	_, err := entities.LocalSocketPath("nvdaMcpBridge", entities.LocalSocketDirs{})
	if err == nil {
		t.Fatal("LocalSocketPath succeeded with no runtime directory and no home")
	}
	if !strings.Contains(err.Error(), "XDG_RUNTIME_DIR") {
		t.Errorf("error %q does not name what was missing", err)
	}
}

// The override: an address that is already a path is used verbatim, on a host
// with no home directory as much as on one with. What would fork the shipped
// defaults per host is a path in the DEFAULTS, not a path being expressible.
func TestLocalSocketPathUsesAnAbsolutePathVerbatim(t *testing.T) {
	got, err := entities.LocalSocketPath("/tmp/somewhere/else.sock", entities.LocalSocketDirs{})
	if err != nil {
		t.Fatalf("LocalSocketPath: %v", err)
	}
	if got != "/tmp/somewhere/else.sock" {
		t.Errorf("path = %q, want the override untouched", got)
	}
}

// The limit is checked at CONSTRUCTION, and the message says the three things
// the kernel's own `connect: invalid argument` says none of: which endpoint,
// which path, and what the limit is.
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

// An override is length-checked too: a long path is a long path however it was
// arrived at, and a user who wrote one deserves the same message.
func TestLocalSocketPathRefusesAnOverlongOverride(t *testing.T) {
	_, err := entities.LocalSocketPath("/tmp/"+strings.Repeat("b", 120)+".sock", entities.LocalSocketDirs{})
	if err == nil {
		t.Fatal("LocalSocketPath accepted an override no unix socket can carry")
	}
}

// The inverse, and the reason both platforms can answer the probe in one
// vocabulary: a socket file stands for the endpoint name it was derived from,
// and anything else in that directory stands for nothing.
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

// The derivation and its inverse are one rule read in two directions, and the
// probe is only honest while they agree: a bridge that binds where this says and
// a listing that reports what this says must name the same endpoint.
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
