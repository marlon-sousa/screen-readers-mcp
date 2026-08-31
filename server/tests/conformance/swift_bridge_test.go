//go:build conformance && darwin

// screenreader-mcp tests -- starting the REAL Swift bridge.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: scaffolding for the conformance tier's macOS half. It builds and launches
// the VoiceOver bridge's own conformance harness
// (bridges/voiceover/Tests/ConformanceBridge) and hands back the endpoint it is
// listening on, so the scenario beside it can drive the real server binary
// against it.
// USED BY: real_swift_bridge_session_test.go. It lives in a _test.go file rather
// than in testsupport/ for python_bridge_test.go's reason: testsupport/ is where
// the FAKE bridge lives, and these must never be alternatives to each other.
//
// WHY IT IS BUILD-TAGGED `darwin`, WHICH IS NOT THE SAME AS SKIPPING. This tier's
// standing rule is that failing to reach the real bridge is a HARD FAILURE and
// never a skip, because a conformance run that quietly used the Go fake would
// assert the guarantee without providing it. That rule is about FALLING BACK, and
// nothing here falls back: on Windows and Linux this file does not compile in at
// all, because a Swift bridge for a macOS-only screen reader cannot exist there.
// That is spec 0042's first principle applied to a test tier -- the server is
// everywhere, a bridge is somewhere -- and it is why the Python scenarios stay
// untagged and run on every host while these run wherever VoiceOver could.
//
// On macOS there is no escape hatch: no Swift toolchain, or a harness that will
// not build, FAILS. That is the same rule the Python side applies to a missing
// interpreter.
//
// THE THIRD BINDING IS WHAT THIS EXISTS FOR. specs/wire/v1/ has three
// implementations -- a generated Go binding, a hand-written Python module and a
// hand-written Swift one -- and until 13.11 the Swift one had never exchanged a
// byte with the server. `scripts/drift.py --swift` reads its SOURCE against the
// schema, which catches a field that was never written; only this catches a field
// that is written differently from how the server reads it.
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

// swiftBuildTimeout bounds the one-off `swift build`. Generous, because a cold
// runner compiles the whole package -- the domain, the adapters, the wire binding
// and the fakes -- before anything can listen.
const swiftBuildTimeout = 10 * time.Minute

// swiftBridge is one running real Swift bridge.
type swiftBridge struct {
	// Endpoint is what it is listening on, spelled the way the server's
	// --reader flag wants it (`local:/path/to.sock`, `tcp:127.0.0.1:53422`).
	Endpoint string

	command *exec.Cmd
	stdin   io.WriteCloser
	stderr  *syncBuffer
}

// startSwiftBridge builds the harness and launches it on one transport.
//
// The protocol is deliberately identical to the Python harness's -- one JSON line
// on stdout, stdin EOF to stop -- so this file and python_bridge_test.go differ
// only in which process they start, and nobody has to keep two driver protocols
// in step with the one contract this tier exists to test.
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

// buildSwiftHarness compiles the harness and returns the path to it.
//
// BUILT BY `swift build --product`, and its own `--show-bin-path` is asked for
// the location rather than a path being assembled here: SwiftPM's build directory
// carries the architecture and the configuration in its name, so spelling it out
// would be a guess that breaks on the first Apple-silicon runner.
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
		// The LAST line: `--show-bin-path` prints the path, but a build that had
		// anything to say first prints that too.
		lines := strings.Split(binPath, "\n")
		return strings.TrimSpace(lines[len(lines)-1]) + "/ConformanceBridge"
	case <-time.After(swiftBuildTimeout):
		t.Fatalf("building the Swift conformance harness took longer than %s", swiftBuildTimeout)
		return ""
	}
}

// awaitSwiftEndpoint reads the harness's one announcement line.
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

// stop closes the harness's stdin, which is its stop signal, and waits for it.
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

// Stderr is what the bridge has written to stderr so far, for a failing test to
// print. A conformance failure is usually about the far side.
func (b *swiftBridge) Stderr() string { return b.stderr.String() }

// startServerAgainstSwift drives the built server binary over stdio, pointed at
// this bridge, exactly as an MCP host would.
func startServerAgainstSwift(t *testing.T, bridge *swiftBridge) *testsupport.MCPHarness {
	t.Helper()
	return startServerForReader(t, "voiceover", bridge.Endpoint)
}
