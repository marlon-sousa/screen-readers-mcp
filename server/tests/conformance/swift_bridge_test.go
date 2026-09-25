//go:build conformance && darwin

// screenreader-mcp tests -- starting the REAL Swift bridge.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: scaffolding for the conformance tier's macOS half, building and launching the VoiceOver bridge's
// conformance harness.
// USED BY: real_swift_bridge_session_test.go.
// On macOS a missing Swift toolchain or a harness that will not build fails the run; it never skips.
package conformance_test

import (
	"bufio"
	"encoding/json"
	"io"
	"os/exec"
	"strings"
	"testing"
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

const swiftBuildTimeout = 10 * time.Minute

type swiftBridge struct {
	Endpoint string

	command *exec.Cmd
	stdin   io.WriteCloser
	stderr  *syncBuffer
}

func startSwiftBridge(t *testing.T, transport string) *swiftBridge {
	t.Helper()

	binary := buildSwiftHarness(t)
	command := exec.Command(binary, "--transport", transport)

	stdout, err := command.StdoutPipe()
	if err != nil {
		t.Fatalf("the real Swift bridge's stdout: %v", err)
	}
	stdin, err := command.StdinPipe()
	if err != nil {
		t.Fatalf("the real Swift bridge's stdin: %v", err)
	}
	stderr := &syncBuffer{}
	command.Stderr = stderr

	if err := command.Start(); err != nil {
		t.Fatalf("starting the real Swift bridge (%s): %v", strings.Join(command.Args, " "), err)
	}

	bridge := &swiftBridge{command: command, stdin: stdin, stderr: stderr}
	t.Cleanup(func() { bridge.stop(t) })

	bridge.Endpoint = awaitSwiftEndpoint(t, bridge, stdout)
	t.Logf("the real Swift bridge is listening on %s", bridge.Endpoint)
	return bridge
}

// SwiftPM's build directory name carries the architecture and configuration, so SwiftPM is asked for it.
func buildSwiftHarness(t *testing.T) string {
	t.Helper()

	packagePath := repoPath(t, "bridges", "voiceover")
	run := func(arguments ...string) string {
		command := exec.Command("swift", append(arguments, "--package-path", packagePath)...)
		output, err := command.CombinedOutput()
		if err != nil {
			t.Fatalf("swift %s: %v\n%s", strings.Join(arguments, " "), err, output)
		}
		return strings.TrimSpace(string(output))
	}

	done := make(chan string, 1)
	go func() {
		run("build", "--product", "ConformanceBridge")
		done <- run("build", "--product", "ConformanceBridge", "--show-bin-path")
	}()

	select {
	case binPath := <-done:
		// The last line: a build that had anything to say prints it before the path.
		lines := strings.Split(binPath, "\n")
		return strings.TrimSpace(lines[len(lines)-1]) + "/ConformanceBridge"
	case <-time.After(swiftBuildTimeout):
		t.Fatalf("building the Swift conformance harness took longer than %s", swiftBuildTimeout)
		return ""
	}
}

func awaitSwiftEndpoint(t *testing.T, bridge *swiftBridge, stdout io.Reader) string {
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
			result.err = json.Unmarshal([]byte(line), &result)
		}
		announced <- result
	}()

	select {
	case result := <-announced:
		if result.err != nil {
			t.Fatalf("the real Swift bridge never announced an endpoint (%v).\nIt said: %q\nstderr:\n%s",
				result.err, result.line, bridge.stderr.String())
		}
		if result.Endpoint == "" {
			t.Fatalf("the real Swift bridge announced an empty endpoint: %q\nstderr:\n%s",
				result.line, bridge.stderr.String())
		}
		return result.Endpoint
	case <-time.After(bridgeStartTimeout):
		t.Fatalf("the real Swift bridge did not report an endpoint within %s.\nstderr:\n%s",
			bridgeStartTimeout, bridge.stderr.String())
		return ""
	}
}

func (b *swiftBridge) stop(t *testing.T) {
	t.Helper()
	_ = b.stdin.Close()

	done := make(chan error, 1)
	go func() { done <- b.command.Wait() }()
	select {
	case <-done:
	case <-time.After(15 * time.Second):
		_ = b.command.Process.Kill()
		<-done
		t.Errorf("the real Swift bridge did not exit when its stdin closed.\nstderr:\n%s",
			b.stderr.String())
	}
}

func (b *swiftBridge) Stderr() string { return b.stderr.String() }

func startServerAgainstSwift(t *testing.T, bridge *swiftBridge) *testsupport.MCPHarness {
	t.Helper()
	return startServerForReader(t, "voiceover", bridge.Endpoint)
}
