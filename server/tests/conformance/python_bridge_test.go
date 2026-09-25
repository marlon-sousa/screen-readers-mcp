//go:build conformance

// screenreader-mcp tests -- starting the REAL Python bridge, and the real server.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: scaffolding for the conformance tier, launching the real NVDA bridge and the real server binary.
// USED BY: the scenarios beside it; it stays out of testsupport/ so it can never stand in for the fake bridge.
// Failing to reach the real bridge must be a hard failure, never a skip or a fall-back to the fake.
package conformance_test

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

const bridgeStartTimeout = 60 * time.Second

type pythonBridge struct {
	Endpoint string

	command *exec.Cmd
	stdin   io.WriteCloser
	stderr  *syncBuffer
}

func startPythonBridge(t *testing.T, transport string) *pythonBridge {
	t.Helper()

	script := repoPath(t, "bridges", "nvda", "tests", "support", "conformance_bridge.py")
	interpreter := pythonInterpreter(t)

	arguments := append(append([]string{}, interpreter[1:]...), script, "--transport", transport)
	command := exec.Command(interpreter[0], arguments...)
	// The harness resolves its relative paths from the bridge directory.
	command.Dir = repoPath(t, "bridges", "nvda")

	stdout, err := command.StdoutPipe()
	if err != nil {
		t.Fatalf("the real bridge's stdout: %v", err)
	}
	stdin, err := command.StdinPipe()
	if err != nil {
		t.Fatalf("the real bridge's stdin: %v", err)
	}
	stderr := &syncBuffer{}
	command.Stderr = stderr

	if err := command.Start(); err != nil {
		t.Fatalf("starting the real bridge (%s): %v", strings.Join(command.Args, " "), err)
	}

	bridge := &pythonBridge{command: command, stdin: stdin, stderr: stderr}
	t.Cleanup(func() { bridge.stop(t) })

	bridge.Endpoint = awaitEndpoint(t, bridge, stdout)
	t.Logf("the real Python bridge is listening on %s", bridge.Endpoint)
	return bridge
}

func awaitEndpoint(t *testing.T, bridge *pythonBridge, stdout io.Reader) string {
	t.Helper()

	type announcement struct {
		Endpoint string `json:"endpoint"`
		line     string
		err      error
	}
	announced := make(chan announcement, 1)
	go func() {
		reader := bufio.NewReader(stdout)
		line, err := reader.ReadString('\n')
		result := announcement{line: line, err: err}
		if err == nil {
			err = json.Unmarshal([]byte(line), &result)
			result.err = err
		}
		announced <- result
	}()

	select {
	case result := <-announced:
		if result.err != nil {
			t.Fatalf("the real bridge never announced an endpoint (%v).\nIt said: %q\nstderr:\n%s",
				result.err, result.line, bridge.stderr.String())
		}
		if result.Endpoint == "" {
			t.Fatalf("the real bridge announced an empty endpoint: %q\nstderr:\n%s",
				result.line, bridge.stderr.String())
		}
		return result.Endpoint
	case <-time.After(bridgeStartTimeout):
		t.Fatalf("the real bridge did not report an endpoint within %s.\nstderr:\n%s",
			bridgeStartTimeout, bridge.stderr.String())
		return ""
	}
}

func (b *pythonBridge) stop(t *testing.T) {
	t.Helper()
	_ = b.stdin.Close()

	done := make(chan error, 1)
	go func() { done <- b.command.Wait() }()
	select {
	case <-done:
	case <-time.After(15 * time.Second):
		_ = b.command.Process.Kill()
		<-done
		t.Errorf("the real bridge did not exit when its stdin closed.\nstderr:\n%s", b.stderr.String())
	}
}

func (b *pythonBridge) Stderr() string { return b.stderr.String() }

func pythonInterpreter(t *testing.T) []string {
	t.Helper()

	if override := os.Getenv("CONFORMANCE_PYTHON"); strings.TrimSpace(override) != "" {
		candidate := strings.Fields(override)
		if err := probePython(candidate); err != nil {
			t.Fatalf("CONFORMANCE_PYTHON=%q cannot run the bridge: %v", override, err)
		}
		return candidate
	}

	candidates := [][]string{{"python"}, {"python3.13"}, {"python3"}}
	if runtime.GOOS == "windows" {
		candidates = append(candidates, []string{"py", "-3.13"})
	}

	var refused []string
	for _, candidate := range candidates {
		if err := probePython(candidate); err != nil {
			refused = append(refused, fmt.Sprintf("  %s: %v", strings.Join(candidate, " "), err))
			continue
		}
		return candidate
	}
	t.Fatalf("no Python 3.13 interpreter could run the real bridge, so this run would "+
		"prove nothing about the wire contract. Tried:\n%s\n"+
		"Set CONFORMANCE_PYTHON to a working interpreter command.",
		strings.Join(refused, "\n"))
	return nil
}

func probePython(candidate []string) error {
	arguments := append(append([]string{}, candidate[1:]...),
		"-c", "import sys; sys.exit(0 if sys.version_info >= (3, 13) else 1)")
	command := exec.Command(candidate[0], arguments...)
	if output, err := command.CombinedOutput(); err != nil {
		return fmt.Errorf("%w (%s)", err, strings.TrimSpace(string(output)))
	}
	return nil
}

func startServer(t *testing.T, endpoint string) *testsupport.MCPHarness {
	t.Helper()
	return startServerForReader(t, "nvda", endpoint)
}

func startServerForReader(t *testing.T, reader, endpoint string) *testsupport.MCPHarness {
	t.Helper()

	binary := buildServer(t)
	command := exec.Command(binary, "--reader", reader+"="+endpoint, "--verbose")
	stderr := &syncBuffer{}
	command.Stderr = stderr
	t.Cleanup(func() {
		if t.Failed() {
			t.Logf("the server said, on stderr:\n%s", stderr.String())
		}
	})

	return testsupport.AttachMCP(t, &sdk.CommandTransport{Command: command})
}

func buildServer(t *testing.T) string {
	t.Helper()

	binary := filepath.Join(t.TempDir(), "screenreader-mcp")
	if runtime.GOOS == "windows" {
		binary += ".exe"
	}
	build := exec.Command("go", "build", "-o", binary, "./cmd/screenreader-mcp")
	build.Dir = repoPath(t, "server")
	build.Env = append(os.Environ(), "CGO_ENABLED=0")
	if output, err := build.CombinedOutput(); err != nil {
		t.Fatalf("building the server: %v\n%s", err, output)
	}
	return binary
}

func repoPath(t *testing.T, elements ...string) string {
	t.Helper()
	root, err := filepath.Abs(filepath.Join("..", "..", ".."))
	if err != nil {
		t.Fatalf("locating the repository root: %v", err)
	}
	path := filepath.Join(append([]string{root}, elements...)...)
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("%s is missing: %v", path, err)
	}
	return path
}

type syncBuffer struct {
	mutex  sync.Mutex
	buffer bytes.Buffer
}

func (b *syncBuffer) Write(p []byte) (int, error) {
	b.mutex.Lock()
	defer b.mutex.Unlock()
	return b.buffer.Write(p)
}

func (b *syncBuffer) String() string {
	b.mutex.Lock()
	defer b.mutex.Unlock()
	return b.buffer.String()
}
