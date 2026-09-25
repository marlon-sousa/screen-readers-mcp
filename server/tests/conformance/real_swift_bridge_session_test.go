//go:build conformance && darwin

// screenreader-mcp tests -- a whole session against the REAL Swift bridge.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: conformance scenario: the built server binary drives a session against the real VoiceOver bridge over a
// real local socket and real loopback TCP.
// VoiceOver is not involved; the harness fakes the reader at the bridge's AdapterFactory port.
package conformance_test

import (
	"slices"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// Literals shared with bridges/voiceover/Tests/ConformanceBridge/main.swift; keep both sides in step.
const (
	swiftReaderName      = "voiceover"
	swiftReaderVersion   = "macOS 0.0.0-conformance"
	swiftBridgeVersion   = "0.0.0-conformance"
	swiftScriptedCommand = "vo+m"
	// The bridge reports the chord it resolved `vo` to, not the id that went out.
	swiftResolvedCommand = "control+option+m"
	swiftFirstLine       = "conformance harness, text area"
	swiftSecondLine      = "one of two"
	swiftCaptureVoice    = "screen-readers-mcp capture voice"
)

var swiftCapabilities = []string{
	"focus", "gestures", "guidance", "interact", "speech", "typing",
}

func connectSwift(
	t *testing.T, harness *testsupport.MCPHarness, bridge *swiftBridge, persona string,
) connectedSession {
	t.Helper()

	// Live, because the bridge refuses a silent handshake where the capture voice is not registered, as on any CI runner.
	result := harness.Call(t, "connect_reader", map[string]any{
		"reader": swiftReaderName, "mode": "live", "persona": persona,
	})
	if result.IsError {
		t.Fatalf("connect_reader against the real Swift bridge failed: %s\nthe bridge said:\n%s",
			result.Text, bridge.Stderr())
	}

	var session connectedSession
	result.Decode(t, &session)

	if session.Reader != swiftReaderName || session.ReaderVersion != swiftReaderVersion {
		t.Errorf("reader = %q %q, want %q %q as the real bridge announced it",
			session.Reader, session.ReaderVersion, swiftReaderName, swiftReaderVersion)
	}
	if session.Endpoint != bridge.Endpoint {
		t.Errorf("endpoint = %q, want the one the bridge is listening on, %q",
			session.Endpoint, bridge.Endpoint)
	}
	if session.Mode != "live" {
		t.Errorf("mode = %q, want the live mode hello established", session.Mode)
	}
	if session.Synth != swiftCaptureVoice {
		t.Errorf("synth = %q, want the capture voice %q", session.Synth, swiftCaptureVoice)
	}
	if session.LogPath == "" {
		t.Error("log path is empty; the session transcript is always reported")
	}
	if session.Persona != persona {
		t.Errorf("persona = %q, want the declared one back", session.Persona)
	}

	got := slices.Clone(session.Capabilities)
	slices.Sort(got)
	if !slices.Equal(got, swiftCapabilities) {
		t.Errorf("capabilities = %v, want %v exactly as the real Swift bridge announces them",
			got, swiftCapabilities)
	}

	if !strings.Contains(session.SilenceCap, "UNATTENDED") {
		t.Errorf("the harness declared an empty room and the server did not report one:\n%s",
			session.SilenceCap)
	}
	return session
}

func TestARealSwiftSessionOverTheLocalEndpoint(t *testing.T) {
	bridge := startSwiftBridge(t, "local")
	harness := startServerAgainstSwift(t, bridge)

	session := connectSwift(t, harness, bridge, "validator")

	if session.ReaderGuidanceText == "" {
		t.Fatal("readerGuidanceText is empty; the handshake document did not survive the " +
			"crossing, or the bridge did not send one")
	}
	if session.ReaderGuidance == "" {
		t.Error("readerGuidance is empty; the resource must still be named")
	}
	if !strings.Contains(session.ReaderGuidanceText, "Driving VoiceOver on macOS") {
		t.Errorf("the guidance is not this reader's own:\n%s", session.ReaderGuidanceText)
	}
	if !strings.Contains(session.ReaderGuidanceText, "validator") {
		t.Error("the declared persona's section is missing from the handshake document")
	}
	if session.Stance != entities.PersonaValidator.Stance() {
		t.Errorf("stance = %q, want the persona's stance in full", session.Stance)
	}

	// The server must answer the resource from the handshake copy, without calling `getGuidance` again.
	framed := harness.ReadReaderGuidance(t)
	if !strings.Contains(framed, "Driving VoiceOver on macOS") {
		t.Errorf("screenreader://reader-guidance did not carry the bridge's own text:\n%s", framed)
	}

	exerciseSwiftSpeech(t, harness, bridge)
	disconnect(t, harness)
}

func TestARealSwiftSessionOverLoopbackTCP(t *testing.T) {
	bridge := startSwiftBridge(t, "tcp")
	harness := startServerAgainstSwift(t, bridge)

	connectSwift(t, harness, bridge, "user")
	exerciseSwiftSpeech(t, harness, bridge)
	disconnect(t, harness)
}

func exerciseSwiftSpeech(t *testing.T, harness *testsupport.MCPHarness, bridge *swiftBridge) {
	t.Helper()

	var before struct {
		Index int `json:"index"`
	}
	harness.Call(t, "get_next_speech_index", nil).Decode(t, &before)

	result := harness.Call(t, "press_gesture", map[string]any{
		"gestures": []string{swiftScriptedCommand},
		"grace_ms": 1000,
	})
	if result.IsError {
		t.Fatalf("press_gesture against the real Swift bridge: %s\nthe bridge said:\n%s",
			result.Text, bridge.Stderr())
	}

	var pressed struct {
		Pressed []struct {
			Gesture    string `json:"gesture"`
			SpeechFrom int    `json:"speechFrom"`
			SpeechTo   int    `json:"speechTo"`
		} `json:"pressed"`
		Speech []struct {
			Text  string `json:"text"`
			Index int    `json:"index"`
		} `json:"speech"`
		SpeechFrom int `json:"speechFrom"`
		SpeechTo   int `json:"speechTo"`
	}
	result.Decode(t, &pressed)

	if len(pressed.Pressed) != 1 {
		t.Fatalf("pressed = %+v, want exactly one press", pressed.Pressed)
	}
	if pressed.Pressed[0].Gesture != swiftResolvedCommand {
		t.Errorf("gesture = %q, want the bridge's resolved spelling %q",
			pressed.Pressed[0].Gesture, swiftResolvedCommand)
	}

	if len(pressed.Speech) != 2 {
		t.Fatalf("speech = %+v, want the two lines the harness scripts", pressed.Speech)
	}
	if pressed.Speech[0].Text != swiftFirstLine || pressed.Speech[1].Text != swiftSecondLine {
		t.Errorf("speech = %+v, want %q then %q in order",
			pressed.Speech, swiftFirstLine, swiftSecondLine)
	}

	if pressed.SpeechFrom != before.Index {
		t.Errorf("speechFrom = %d, want the bookmark %d", pressed.SpeechFrom, before.Index)
	}
	if pressed.SpeechTo != before.Index+2 {
		t.Errorf("speechTo = %d, want %d -- half-open past both utterances",
			pressed.SpeechTo, before.Index+2)
	}
	if pressed.Speech[0].Index != before.Index {
		t.Errorf("first utterance index = %d, want %d", pressed.Speech[0].Index, before.Index)
	}

	var fetched capturedWindow
	harness.Call(t, "get_speech", map[string]any{"since_index": before.Index}).Decode(t, &fetched)
	if len(fetched.Entries) != 2 {
		t.Fatalf("get_speech returned %d entries, want the same two the press reported",
			len(fetched.Entries))
	}
	if fetched.Entries[0].Text != swiftFirstLine || fetched.Entries[1].Text != swiftSecondLine {
		t.Errorf("get_speech = %+v, want the same two lines in the same order", fetched.Entries)
	}
	if fetched.ToIndex != pressed.SpeechTo {
		t.Errorf("get_speech toIndex = %d, want the press's speechTo %d",
			fetched.ToIndex, pressed.SpeechTo)
	}
}

func TestToolsThisReaderCannotServeAreRefusedByCapability(t *testing.T) {
	bridge := startSwiftBridge(t, "local")
	harness := startServerAgainstSwift(t, bridge)
	connectSwift(t, harness, bridge, "user")
	defer disconnect(t, harness)

	for tool, capability := range map[string]string{
		"get_braille":           "braille",
		"get_state":             "state",
		"get_config":            "config",
		"get_log":               "log",
		"get_document_snapshot": "document",
	} {
		if !harness.Advertises(t, tool) {
			t.Errorf("%s is not advertised; every tool is listed from startup", tool)
			continue
		}
		result := harness.Call(t, tool, nil)
		if !result.IsError {
			t.Errorf("%s answered on a reader that does not announce %q", tool, capability)
			continue
		}
		if !strings.Contains(result.Text, capability) {
			t.Errorf("%s was refused without naming %q: %s", tool, capability, result.Text)
		}
	}
}
