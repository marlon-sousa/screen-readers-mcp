//go:build conformance && darwin

// screenreader-mcp tests -- a whole session against the REAL Swift bridge.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: conformance scenario, named after the use case, behind
// //go:build conformance && darwin. Board entry 13.11.
// DRIVES: the built server binary over stdio (swift_bridge_test.go), which dials
// the real VoiceOver bridge over a real local socket and real loopback TCP.
//
// WHAT THIS PROVES THAT NOTHING ELSE DOES, and it is a NEW guarantee rather than
// a second copy of the Python one. The wire contract has three implementations:
// a Go binding generated from specs/wire/v1/schema.json, a hand-written Python
// module, and a hand-written Swift one. Before this entry the Swift binding had
// been checked only by `scripts/drift.py --swift`, which reads its SOURCE against
// the schema -- so it could catch a field that was never written, and could not
// catch a field written differently from how the server reads it. Nothing had
// ever put those two implementations on opposite ends of a socket.
//
// So the assertions below are deliberately about VALUES CROSSING THE WIRE --
// field names, enum spellings, index arithmetic, the shape of a result -- rather
// than about server behaviour, which the headless tier already covers with far
// better failure messages. Where an assertion looks redundant with the Python
// scenario, it is not: the same claim about a DIFFERENT binding is a different
// claim.
//
// VOICEOVER IS NOT INVOLVED. The reader is faked at the bridge's own
// AdapterFactory port, because what is under test here is the wire, not the
// reader -- and because this must pass on a CI runner with no VoiceOver session,
// no grant and no capture voice, and on a developer's machine without touching
// the screen reader they are using. Driving the real reader is the live tier,
// and its checklist is in this entry's pull request.
package conformance_test

import (
	"slices"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// What the Swift harness announces and scripts. These are literals from
// bridges/voiceover/Tests/ConformanceBridge/main.swift: this tier is the seam
// between two languages, so the agreement is spelled out on both sides rather
// than shared through a constant neither could import.
const (
	swiftReaderName    = "voiceover"
	swiftReaderVersion = "macOS 0.0.0-conformance"
	swiftBridgeVersion = "0.0.0-conformance"
	// A KEYSTROKE, and `vo+m` rather than `control+option+m`, which is the sharpest
	// thing this tier can show about the id: the wire never looks inside the
	// string, and `vo` means whatever the machine on the far side has its VoiceOver
	// modifier bound to. It was a COMMAND NAME until board entry 13.31 -- the two
	// readers' notations differed completely, and this constant was where that was
	// visible -- and the two have converged now that a VoiceOver session presses
	// what a VoiceOver user presses. What the tier still proves is unchanged: an
	// opaque id crosses two languages untouched.
	swiftScriptedCommand = "vo+m"
	// WHAT COMES BACK, which is not what went out and is the point. The bridge
	// reports what it UNDERSTOOD -- `vo` resolved against the modifier that
	// machine has bound -- so a record of a run says which keys really went to the
	// window server. The server passes both directions through untouched.
	swiftResolvedCommand = "control+option+m"
	swiftFirstLine       = "conformance harness, text area"
	swiftSecondLine      = "one of two"
	// What `hello` names as the voice a session is hearing or silencing. On NVDA
	// this is a synthesizer driver; here it is the capture voice, because that is
	// the thing that would be rendering silence.
	swiftCaptureVoice = "screen-readers-mcp capture voice"
)

// swiftCapabilities is what this bridge announces, in sorted order.
//
// SIX, NOT ELEVEN, AND THE GAP IS THE POINT. The Python bridge announces every
// group the contract defines; this one announces what VoiceOver can actually do,
// and the five it omits -- braille, state, config, log, document -- are absent
// from the READER rather than unimplemented here. That difference travelling
// intact is the capability gate's whole reason for existing, and this is the only
// tier where two real, independently written bridges can be seen to disagree
// about it correctly.
var swiftCapabilities = []string{
	"focus", "gestures", "guidance", "interact", "speech", "typing",
}

// connectSwift performs the handshake and checks that every field the real Swift
// bridge sent survived the crossing.
//
// The densest assertion in this file: `hello` carries a nested object, a string
// enum, a string array, an integer and -- since 13.11 -- a nested guidance
// document, so a binding that got any field NAME wrong fails here and nowhere
// else.
func connectSwift(
	t *testing.T, harness *testsupport.MCPHarness, bridge *swiftBridge, persona string,
) connectedSession {
	t.Helper()

	// LIVE, not silent, and that is a real constraint rather than a preference:
	// this bridge REFUSES a silent handshake on a machine where the capture voice
	// is not registered and published (13.6), which is every CI runner and any
	// developer machine that has not installed it. A live session is not refused
	// in that state, deliberately -- writing the voice applies live in both
	// directions, so a live session that starts unhealthy can become healthy while
	// it runs. That asymmetry is what makes this tier runnable at all.
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
	// The capture mode is a wire ENUM on both sides, spelled independently -- a
	// Swift `CaptureMode` and a Go one, agreeing only because both were written
	// against the schema.
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

	// THE MACHINE THIS HARNESS DECLARES IS UNATTENDED, and that fact travels as
	// itself (spec 0035) rather than being inferred from the silence cap.
	if !strings.Contains(session.SilenceCap, "UNATTENDED") {
		t.Errorf("the harness declared an empty room and the server did not report one:\n%s",
			session.SilenceCap)
	}
	return session
}

// A whole session, end to end, against the real Swift bridge over the LOCAL
// endpoint -- which is the transport this bridge's shipped default uses, and
// therefore the one an agent will actually meet.
func TestARealSwiftSessionOverTheLocalEndpoint(t *testing.T) {
	bridge := startSwiftBridge(t, "local")
	harness := startServerAgainstSwift(t, bridge)

	session := connectSwift(t, harness, bridge, "validator")

	// THE GUIDANCE DOCUMENT CROSSED IN THE HANDSHAKE (protocol.md §3, spec 0022
	// A.5), composed by the real Swift bridge for the persona this very call
	// declared. This is the seam where a new optional wire field can silently fail
	// to decode -- the fake bridge is built from the same Go binding the server
	// reads with, so it cannot disagree about the field, and the Swift one can.
	if session.ReaderGuidanceText == "" {
		t.Fatal("readerGuidanceText is empty; the handshake document did not survive the " +
			"crossing, or the bridge did not send one")
	}
	if session.ReaderGuidance == "" {
		t.Error("readerGuidance is empty; the resource must still be named")
	}
	// It is THIS reader's document rather than a generic one, and it is the
	// persona's half rather than only the common half.
	if !strings.Contains(session.ReaderGuidanceText, "Driving VoiceOver on macOS") {
		t.Errorf("the guidance is not this reader's own:\n%s", session.ReaderGuidanceText)
	}
	if !strings.Contains(session.ReaderGuidanceText, "validator") {
		t.Error("the declared persona's section is missing from the handshake document")
	}
	// The stance the SERVER attaches is normative and unaffected by whatever the
	// bridge wrote (spec 0029, 4.1).
	if session.Stance != entities.PersonaValidator.Stance() {
		t.Errorf("stance = %q, want the persona's stance in full", session.Stance)
	}

	// AND THE SAME DOCUMENT IS SERVED AS A RESOURCE, framed by the server. The
	// contract says a server that received the handshake copy must not call
	// `getGuidance` again, so the resource read here is answered from what already
	// crossed -- and it must still be the bridge's text, wrapped rather than
	// summarised.
	framed := harness.ReadReaderGuidance(t)
	if !strings.Contains(framed, "Driving VoiceOver on macOS") {
		t.Errorf("screenreader://reader-guidance did not carry the bridge's own text:\n%s", framed)
	}

	exerciseSwiftSpeech(t, harness, bridge)
	disconnect(t, harness)
}

// The same handshake over loopback TCP, because a bridge that only worked on one
// transport would be a bridge whose framing was accidentally coupled to its
// socket.
//
// Deliberately SHORTER than the local-endpoint scenario: what differs between the
// two is the transport, and re-asserting every field would be re-testing the
// binding rather than the socket.
func TestARealSwiftSessionOverLoopbackTCP(t *testing.T) {
	bridge := startSwiftBridge(t, "tcp")
	harness := startServerAgainstSwift(t, bridge)

	connectSwift(t, harness, bridge, "user")
	exerciseSwiftSpeech(t, harness, bridge)
	disconnect(t, harness)
}

// exerciseSwiftSpeech is the round trip this tier exists for: a gesture goes out
// as a wire command, the fake reader speaks as a consequence, and the utterances
// come back with indices that add up.
//
// IT IS ONE CALL, NOT THREE. `press_gesture` waits its grace and returns what
// arrived, so the speech below is the same speech `get_speech` would fetch -- and
// asserting BOTH is what proves the two agree about the ring's arithmetic across
// the language boundary.
func exerciseSwiftSpeech(t *testing.T, harness *testsupport.MCPHarness, bridge *swiftBridge) {
	t.Helper()

	// The bookmark before acting, which is the pattern the tool descriptions
	// teach: an integer crossing the wire in both directions.
	var before struct {
		Index int `json:"index"`
	}
	harness.Call(t, "get_next_speech_index", nil).Decode(t, &before)

	// A GRACE LONG ENOUGH FOR A SCRIPTED REPLY that arrives on the session's own
	// thread. The default is 100 ms and the harness emits synchronously inside the
	// press, so this is generous rather than load-bearing -- but a value tuned in
	// one capture mode may be wrong in the other, and this tier should not be the
	// place that discovers it.
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
	// THE ID WENT OUT OPAQUE AND CAME BACK RESOLVED, which is the sharpest thing
	// this tier can show about `gesture`. The server never looks inside the string:
	// it carried `vo+m` down and `control+option+m` back, and both are the bridge's
	// business. It asserted the two were EQUAL until board entry 13.31 -- the id
	// was then a command name with spaces, the kind of value a binding can quietly
	// normalise -- and what replaced that is a stronger claim, because a server
	// that normalised either direction would now fail here rather than agree with
	// itself.
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

	// THE INDEX ARITHMETIC, which is where two implementations of a half-open
	// range most easily disagree: the press's own span must start where the
	// bookmark was and end one past the last utterance.
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

	// AND THE SAME WORDS FETCHED THE OTHER WAY. `get_speech` from the bookmark
	// must return exactly what the press already reported -- if the two disagreed,
	// one of them would be inventing indices.
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

// A capability this reader does not have is refused with a capability error, and
// the refusal names the missing capability rather than the tool.
//
// THIS IS THE HALF THE PYTHON TIER CANNOT TEST. That bridge announces every group
// the contract defines, so its conformance run has no unannounced capability to
// exercise -- `unannouncedTools` over there is an empty list kept as a slot. Here
// five groups are genuinely absent from the READER, so the gate can be seen doing
// its job end to end against a real bridge for the first time.
func TestToolsThisReaderCannotServeAreRefusedByCapability(t *testing.T) {
	bridge := startSwiftBridge(t, "local")
	harness := startServerAgainstSwift(t, bridge)
	connectSwift(t, harness, bridge, "user")
	defer disconnect(t, harness)

	// One tool per capability VoiceOver does not offer. Each is advertised -- spec
	// 0022 option (c) advertises everything from startup -- and each must refuse.
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
		// It must say WHAT is missing. "unknown tool" would send an agent looking
		// for a server bug rather than reading the reader's capability list.
		if !strings.Contains(result.Text, capability) {
			t.Errorf("%s was refused without naming %q: %s", tool, capability, result.Text)
		}
	}
}
