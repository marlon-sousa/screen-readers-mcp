//go:build conformance

// screenreader-mcp tests -- a whole session against the REAL Python bridge.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: conformance scenario, named after the use case, behind
// //go:build conformance so `go test ./...` stays fast and the Windows-only run
// opts in explicitly. Deliverable 19 of spec 0013.
// DRIVES: the built server binary over stdio (python_bridge_test.go), which
// dials the real NVDA bridge over a real transport.
//
// WHAT THIS TIER PROVES THAT NO OTHER TIER CAN. Two INDEPENDENT implementations
// of specs/wire/v1/ -- a generated Go binding and a hand-written Python module --
// agree about actual bytes. Every other tier's bridge is a Go fake that encodes
// with the same binding the server decodes with, so a bug in the binding is
// invisible there; both sides would be wrong together, in agreement. That is the
// same argument AGENTS.md makes about unit fakes never proving a real adapter
// behaves like its fake, one level up, and it is what replaced the same-bytes
// drift guarantee when the server stopped being Python.
//
// So the assertions below are deliberately about VALUES CROSSING THE WIRE --
// field names, enum spellings, index arithmetic, the shape of a result -- rather
// than about server behaviour, which the headless tier already covers with far
// better failure messages.
//
// Everything except the reader itself is real: NVDA is faked at the bridge's own
// AdapterFactory port, because what is under test here is the wire, not NVDA
// (that is entry 11's live run).
package conformance_test

import (
	"slices"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// What the harness on the far side announces and scripts. These are literals
// from bridges/nvda/tests/support/conformance_bridge.py: this tier is the seam
// between two languages, so the agreement is spelled out on both sides rather
// than shared through a constant neither could import.
const (
	readerName    = "nvda"
	readerVersion = "2026.1.0-conformance"
	scriptedKey   = "kb:NVDA+f7"
	firstLine     = "Elements list dialog"
	secondLine    = "Links radio button checked"
	brailleCells  = "elements lst dlg"
	fakeSynth     = "espeak"
	announcedHint = "Taking over: I need a password."
	askedPrompt   = "Plug the braille display in, then acknowledge."
	// Punctuation and an accented character, deliberately: this is what
	// KeyboardInputGesture.fromName cannot reach on every keyboard layout, and
	// exactly the case spec 0019 exists for.
	typedText = "café — 50%"
)

// ungatedTools and gatedTools together are the WHOLE advertised surface, which
// spec 0022 (option (c)) made a constant: both lists are expected before
// connecting, while connected, and after disconnecting.
//
// The split between them is still meaningful and still checked -- it is what
// `screenreader://tools` reports as each tool's gate, and what decides whether a
// CALL is refused -- but it no longer decides what is LISTED.
//
// `announce` joined this list in entry 11a. focus/state/config joined in entry
// 11.1 (spec 0015), which served the four introspection commands and widened
// NVDA_CAPABILITIES to all eight -- and did so with ZERO changes to the
// server's production code. These expectations moving from unannounced to
// gated, with nothing under server/ changing but this test, is what proves the
// capability gate is structural rather than hand-maintained.
//
// unannouncedTools is consequently empty: this bridge now serves every group
// the wire defines. Kept (rather than deleted) as the slot for the next
// capability the wire defines before a bridge serves it -- that is what
// exercises the "ignore what you do not know" clause of protocol.md §4 against
// a real announcement.
var (
	ungatedTools = []string{"connect_reader", "disconnect_reader", "list_readers", "status"}

	gatedTools = []string{
		"announce",                  // interact
		"ask_user",                  // interact
		"get_braille",               // braille
		"get_config",                // config
		"get_focus_info",            // focus
		"get_last_speech",           // speech
		"get_log",                   // log
		"get_log_position",          // log
		"get_next_speech_index",     // speech
		"get_speech",                // speech
		"get_state",                 // state
		"set_state",                 // state
		"press_gesture",             // gestures
		"run_sequence",              // gated by its steps, not by one capability
		"set_config",                // config
		"set_log_level",             // log
		"type_text",                 // typing
		"wait_for_log",              // log
		"wait_for_speech",           // speech
		"wait_for_speech_to_finish", // speech
		"wait_for_user_reply",       // interact
	}

	unannouncedTools = []string{}
)

// capturedWindow is get_speech's and get_braille's answer since spec 0021: one
// entry per utterance or display update, each with its own ring index and the
// log journal position it was captured at, plus the half-open range covered.
type capturedWindow struct {
	Entries []struct {
		Text        string `json:"text"`
		Index       int    `json:"index"`
		LogPosition int    `json:"logPosition"`
		EmittedAt   string `json:"emittedAt"`
	} `json:"entries"`
	FromIndex int `json:"fromIndex"`
	ToIndex   int `json:"toIndex"`
}

func (w capturedWindow) texts() []string {
	said := make([]string, 0, len(w.Entries))
	for _, entry := range w.Entries {
		said = append(said, entry.Text)
	}
	return said
}

// TestAWholeSessionOverLoopbackTCP is the conformance run over TCP. Its named
// pipe twin lives beside it, behind an additional `windows` tag.
func TestAWholeSessionOverLoopbackTCP(t *testing.T) {
	runWholeSession(t, "tcp")
}

// runWholeSession is the scenario spec 0013 deliverable 19 describes: handshake,
// a capability-gated tool list, one command per capability group, and a clean
// teardown -- repeated over each transport.
func runWholeSession(t *testing.T, transport string) {
	t.Helper()

	bridge := startPythonBridge(t, transport)
	harness := startServer(t, bridge.Endpoint)

	// THE WHOLE SURFACE, BEFORE ANYTHING IS CONNECTED (spec 0022, option (c)).
	// Asserted across the real transport because that is where entry 11.6 was
	// found: a client's cached list is correct here only if the list never moves.
	wholeSurface := append(slices.Clone(ungatedTools), gatedTools...)
	assertAdvertises(t, harness, wholeSurface, unannouncedTools)

	session := connect(t, harness, bridge)
	assertAdvertises(t, harness, wholeSurface, unannouncedTools)

	exerciseGestures(t, harness)
	exerciseSpeech(t, harness)
	exerciseBraille(t, harness)
	exerciseAnnounce(t, harness)
	exerciseAskUser(t, harness)
	exerciseTyping(t, harness)
	exerciseStateWrite(t, harness)
	exerciseLog(t, harness)
	exerciseLogObservation(t, harness)
	exerciseGuidance(t, harness)
	assertStatusIsProvenOnTheWire(t, harness)
	assertInfoDescribesTheSession(t, harness, session)

	disconnect(t, harness)
	// Unchanged by the session ending, exactly as by its beginning. What a
	// disconnect changes is what a CALL does, which exerciseGuidance and the
	// integration tier both assert on.
	assertAdvertises(t, harness, wholeSurface, unannouncedTools)

	// A second session on the same bridge process: `bye` really did tear the
	// first one down, and the bridge went back to accepting. A teardown that
	// only looked clean from this side would fail here.
	connect(t, harness, bridge)
	disconnect(t, harness)
}

// connectedSession is connect_reader's answer -- everything `hello` established,
// after it has crossed the binding.
type connectedSession struct {
	Reader        string   `json:"reader"`
	ReaderVersion string   `json:"readerVersion"`
	Endpoint      string   `json:"endpoint"`
	Capabilities  []string `json:"capabilities"`
	Mode          string   `json:"mode"`
	Persona       string   `json:"persona"`
	Stance        string   `json:"stance"`
	Synth         string   `json:"synth"`
	LogPath       string   `json:"logPath"`

	// The reader's own guidance, both as a pointer and in full (spec 0022 A.5).
	ReaderGuidance     string `json:"readerGuidance"`
	ReaderGuidanceText string `json:"readerGuidanceText"`

	// What this machine does about a silence, and who is at it (specs 0032,
	// 0035) -- one sentence composed from two facts the real Python bridge
	// declared independently.
	SilenceCap string `json:"silenceCap"`
}

// connect performs the handshake and checks that every field the real bridge
// sent survived the crossing -- including, since spec 0022 A.5, the reader's own
// guidance document, which now rides back in `hello` rather than being fetched.
//
// This is the single densest assertion in the tier: `hello` carries a nested
// object, a string enum, a string array and an integer, so a binding that got
// any field NAME wrong -- `logPath` rather than `transcriptPath`, `reader` as
// a string rather than an object -- fails here and nowhere else.
func connect(t *testing.T, harness *testsupport.MCPHarness, bridge *pythonBridge) connectedSession {
	t.Helper()

	result := harness.Connect(t)
	if result.IsError {
		t.Fatalf("connect_reader against the real bridge failed: %s\nthe bridge said:\n%s",
			result.Text, bridge.Stderr())
	}

	var session connectedSession
	result.Decode(t, &session)

	if session.Reader != readerName || session.ReaderVersion != readerVersion {
		t.Errorf("reader = %q %q, want %q %q as the real bridge announced it",
			session.Reader, session.ReaderVersion, readerName, readerVersion)
	}
	if session.Endpoint != bridge.Endpoint {
		t.Errorf("endpoint = %q, want the one the bridge is listening on, %q",
			session.Endpoint, bridge.Endpoint)
	}
	// The capture mode is a wire ENUM on both sides, spelled independently.
	if session.Mode != "silent" {
		t.Errorf("mode = %q, want the silent mode hello established", session.Mode)
	}
	if session.Synth != fakeSynth {
		t.Errorf("synth = %q, want %q", session.Synth, fakeSynth)
	}
	// The session transcript path is always reported.
	if session.LogPath == "" {
		t.Errorf("log path = %q, want it reported", session.LogPath)
	}
	// The persona (spec 0029) crossed the wire as a plain string, was accepted
	// by the real Python validator, and came back with its stance attached.
	if session.Persona != "user" {
		t.Errorf("persona = %q, want the declared one back", session.Persona)
	}
	if session.Stance != entities.PersonaUser.Stance() {
		t.Errorf("stance = %q, want the persona's stance in full", session.Stance)
	}
	// THE GUIDANCE DOCUMENT CROSSED IN THE HANDSHAKE (spec 0022 A.5), composed
	// by the real Python bridge for the persona this very call declared. Proved
	// here rather than only in the integration tier because this is the seam
	// where a new optional wire field can silently fail to decode: the fake
	// bridge is built from the same Go binding the server reads with, so it
	// cannot disagree about the field, and the Python one can.
	if session.ReaderGuidanceText == "" {
		t.Error("readerGuidanceText is empty; the handshake document did not survive " +
			"the crossing, or the bridge did not send one")
	}
	if strings.Contains(session.ReaderGuidanceText, "{{gestures:") {
		t.Errorf("an unsubstituted gesture marker reached the agent in connect's result:\n%s",
			session.ReaderGuidanceText)
	}
	// The pointer survives beside the payload, for a re-read mid-session.
	if session.ReaderGuidance == "" {
		t.Error("readerGuidance is empty; the resource must still be named")
	}

	// ATTENDANCE CROSSED AS ITSELF (spec 0035). The harness declares the one
	// pair that tells the two implementations apart: a human IS at that machine
	// and the machine bounds NOTHING. A server that reconstructed attendance by
	// inverting `silenceCap.enabled` -- which is what this repo did before entry
	// 11.27, and what any bridge-agnostic client might still be tempted to do --
	// would announce this session as an empty room and tell a well-behaved agent
	// to stop narrating. This is the only tier that can catch it: the fake bridge
	// encodes with the very binding the server decodes with, so it cannot
	// disagree about an optional boolean, and the real Python one can.
	if strings.Contains(session.SilenceCap, "UNATTENDED") {
		t.Errorf("the real bridge declared a human and the server reported an empty room:\n%s",
			session.SilenceCap)
	}
	if !strings.Contains(session.SilenceCap, "HUMAN IS EXPECTED") {
		t.Errorf("declared attendance did not survive the crossing:\n%s", session.SilenceCap)
	}

	// `guidance` joined in entry 11.20 (spec 0029). It is the only member here
	// that gates no tool, which is why gatedTools above is unchanged -- and
	// asserting the exact set is what makes that visible rather than assumed.
	want := []string{
		"braille", "config", "focus", "gestures", "guidance",
		"interact", "log", "speech", "state", "typing",
	}
	got := slices.Clone(session.Capabilities)
	slices.Sort(got)
	if !slices.Equal(got, want) {
		t.Errorf("capabilities = %v, want %v exactly as the real bridge announces them", got, want)
	}
	return session
}

// disconnect ends the session politely and insists the bridge accepted the
// `bye`.
func disconnect(t *testing.T, harness *testsupport.MCPHarness) {
	t.Helper()
	if result := harness.Call(t, "disconnect_reader", nil); result.IsError {
		t.Fatalf("disconnect_reader: %s", result.Text)
	}
}

// exerciseLog is the `log` capability group (spec 0020): both commands, the full
// filter set, and one piece of real cross-language STATE.
//
// The bridge under conformance has no NVDA behind it, so the slice's text is
// empty -- and that is fine, because what this tier exists to catch is a binding
// bug, not NVDA's behaviour (see the harness header). Two things here are still
// genuinely end-to-end rather than shape checks:
//
//   - Every filter is populated. GetLogParams marshals seven fields of four
//     different shapes (optional int, int, optional string, three arrays); the
//     bridge validates the field names and REFUSES unknown ones, so a binding
//     that spelled `maxEntries` or `minLevel` wrong comes back as an error here.
//   - set_log_level then a marked command then get_log: `capturedAtLevel` has to
//     come back as the level just set. That only holds if setLogLevel really
//     moved the bridge's own state and the Session recorded it on the NEXT
//     command's window -- neither of which a same-language fake could prove.
func exerciseLog(t *testing.T, harness *testsupport.MCPHarness) {
	t.Helper()

	var level struct {
		Level    string `json:"level"`
		Previous string `json:"previous"`
	}
	harness.Call(t, "set_log_level", map[string]any{"level": "debug"}).Decode(t, &level)
	if level.Level != "debug" {
		t.Errorf("level = %q, want the debug that was asked for", level.Level)
	}
	if level.Previous == "" {
		t.Error("previous level is empty; it is what makes the change reversible")
	}

	// A command AFTER the level change, so its window records the new floor. This
	// is also the command get_log will anchor on, since get_log does not mark
	// itself.
	harness.Call(t, "press_gesture", map[string]any{"gestures": []string{scriptedKey}})

	var slice logSlice
	result := harness.Call(t, "get_log", map[string]any{
		"windows":    1,
		"minLevel":   "debug",
		"contains":   []string{"COMError", "speech"},
		"exclude":    []string{"speech.speech.speak"},
		"fields":     []string{"time", "level", "module", "message"},
		"maxEntries": 25,
	})
	if result.IsError {
		t.Fatalf("get_log with every filter set: %s", result.Text)
	}
	result.Decode(t, &slice)

	if slice.CapturedAtLevel != "debug" {
		t.Errorf("capturedAtLevel = %q, want the debug set_log_level just established -- "+
			"the level did not reach the bridge, or the window did not record it",
			slice.CapturedAtLevel)
	}
	// Real request ids the bridge assigned, in order -- not zero-valued fields a
	// binding forgot to populate. Pointers since spec 0021, because a read
	// anchored by position or time is attributable to NO command and says so with
	// an absent field rather than with id 0, which is a real id.
	if slice.FromCommandID == nil || slice.ToCommandID == nil {
		t.Fatalf("command range = %v..%v, want the ids the bridge actually marked",
			slice.FromCommandID, slice.ToCommandID)
	}
	if *slice.FromCommandID <= 0 || *slice.ToCommandID <= 0 {
		t.Errorf("command range = %d..%d, want real ids",
			*slice.FromCommandID, *slice.ToCommandID)
	}
	if *slice.FromCommandID > *slice.ToCommandID {
		t.Errorf("command range = %d..%d, want it ordered oldest-first",
			*slice.FromCommandID, *slice.ToCommandID)
	}
	// No NVDA behind this bridge, so nothing was logged; the counts must be
	// honest about that rather than inventing entries.
	if slice.Entries != 0 || slice.Matched != 0 || slice.Text != "" {
		t.Errorf("slice = %d/%d %q, want an honest empty answer from a bridge with no NVDA",
			slice.Entries, slice.Matched, slice.Text)
	}

	// Widening to two windows reaches back PAST the set_log_level, and the answer
	// changes to the level in force for the oldest window in the range. That is
	// the conservative direction on purpose: a multi-window slice never claims to
	// have captured more than its earliest window did.
	var widened logSlice
	harness.Call(t, "get_log", map[string]any{"windows": 2}).Decode(t, &widened)
	if widened.CapturedAtLevel != "info" {
		t.Errorf("capturedAtLevel over two windows = %q, want the info in force before "+
			"set_log_level ran", widened.CapturedAtLevel)
	}
	if widened.FromCommandID == nil || *widened.FromCommandID >= *slice.FromCommandID {
		t.Errorf("two windows started at command %v, want something older than %d",
			widened.FromCommandID, *slice.FromCommandID)
	}

	// An unknown field name is the agent's mistake and comes back as an error,
	// not as a slice quietly missing a column.
	if refused := harness.Call(t, "get_log", map[string]any{
		"fields": []string{"levl"},
	}); !refused.IsError {
		t.Error("get_log accepted an unknown field name instead of refusing it")
	}

	// warning/error are minLevel filters, never settable: the bridge refuses even
	// though the enum contains them.
	if refused := harness.Call(t, "set_log_level", map[string]any{
		"level": "error",
	}); !refused.IsError {
		t.Error("set_log_level accepted 'error', which would silence the user's own log")
	}
}

// logSlice is get_log's answer as it reaches an agent.
type logSlice struct {
	Text            string `json:"text"`
	Entries         int    `json:"entries"`
	Matched         int    `json:"matched"`
	Truncated       bool   `json:"truncated"`
	NextPosition    int    `json:"nextPosition"`
	FromCommandID   *int   `json:"fromCommandId"`
	ToCommandID     *int   `json:"toCommandId"`
	CapturedAtLevel string `json:"capturedAtLevel"`
}

// exerciseLogObservation is spec 0021's half of the `log` group: the cursor
// anchor, the two new commands, and the refusal that keeps the anchors apart.
//
// The bridge under conformance has no NVDA behind it, so nothing is journalled
// and every slice comes back empty -- which is fine, because this tier catches
// BINDING bugs, not NVDA's behaviour. What is genuinely end to end here:
//
//   - The mutual-exclusion refusal. Two anchors on one call must come back as an
//     error, and that rule lives in the BRIDGE. A server that quietly dropped one
//     anchor would pass every Go-side test and fail here.
//   - sincePosition survives as a real integer. Position 0 is a legitimate anchor
//     and Go's zero value; a binding that tagged it `omitempty` would silently
//     turn "from the very start" into a command-anchored read of something else,
//     which nothing on either side alone can detect.
//   - waitForLog's miss path. `found: false` after a real timeout at the bridge,
//     rather than an error -- the manners waitForSpeech established.
func exerciseLogObservation(t *testing.T, harness *testsupport.MCPHarness) {
	t.Helper()

	var mark struct {
		Position int    `json:"position"`
		Time     string `json:"time"`
	}
	result := harness.Call(t, "get_log_position", nil)
	if result.IsError {
		t.Fatalf("get_log_position: %s", result.Text)
	}
	result.Decode(t, &mark)
	if mark.Position < 0 {
		t.Errorf("position = %d, want a real journal mark", mark.Position)
	}
	// The wall clock is what lets a mark be lined up against the session
	// transcript, so an empty string here makes the whole field useless.
	if _, err := time.Parse("2006-01-02 15:04:05.000", mark.Time); err != nil {
		t.Errorf("time = %q, want the transcript's own stamp format: %v", mark.Time, err)
	}

	// Something for the interval to contain, and something for the span model to
	// attribute it to.
	harness.Call(t, "press_gesture", map[string]any{"gestures": []string{scriptedKey}})

	var tail logSlice
	result = harness.Call(t, "get_log", map[string]any{"sincePosition": mark.Position})
	if result.IsError {
		t.Fatalf("get_log with a position anchor: %s", result.Text)
	}
	result.Decode(t, &tail)
	if tail.NextPosition < mark.Position {
		t.Errorf("nextPosition = %d, went BACKWARDS from the mark at %d",
			tail.NextPosition, mark.Position)
	}
	// Attributable to no command, and it has to say so with an absent field.
	if tail.FromCommandID != nil || tail.ToCommandID != nil {
		t.Errorf("a position-anchored read reported command range %v..%v, want none",
			tail.FromCommandID, tail.ToCommandID)
	}

	// Position 0 is the start of the session, not "unset" -- the case an
	// `omitempty` on the anchor would silently break.
	if refused := harness.Call(t, "get_log", map[string]any{
		"sincePosition": 0,
	}); refused.IsError {
		t.Errorf("get_log from position 0 was refused: %s", refused.Text)
	}

	// The rule the BRIDGE owns: more than one anchor is an error rather than a
	// precedence puzzle.
	if refused := harness.Call(t, "get_log", map[string]any{
		"sincePosition": mark.Position,
		"lastSeconds":   10,
	}); !refused.IsError {
		t.Error("get_log accepted two anchors at once instead of refusing them")
	}

	// The time anchor on its own is accepted.
	if timed := harness.Call(t, "get_log", map[string]any{
		"lastSeconds": 30,
	}); timed.IsError {
		t.Errorf("get_log with lastSeconds alone: %s", timed.Text)
	}

	// Nothing is journalled behind this bridge, so the wait runs to its timeout --
	// which is exactly the path worth crossing a real binding for: a miss is an
	// ANSWER, and the position it carries stays usable.
	var waited struct {
		Found    bool   `json:"found"`
		Position int    `json:"position"`
		Text     string `json:"text"`
	}
	result = harness.Call(t, "wait_for_log", map[string]any{
		"min_level": "error",
		"timeout":   1,
	})
	if result.IsError {
		t.Fatalf("wait_for_log that matched nothing came back as an error: %s", result.Text)
	}
	result.Decode(t, &waited)
	if waited.Found {
		t.Errorf("wait_for_log found %q, but nothing is journalled behind this bridge", waited.Text)
	}
	if waited.Position < 0 {
		t.Errorf("position = %d, want a usable mark even on a miss", waited.Position)
	}
}

// exerciseGestures is the `gestures` capability group: opaque reader ids over
// the wire, and the speech they caused back in the SAME result (spec 0025).
//
// This tier is the only one where both implementations of the grace window are
// real -- a Go server asking for a window and a Python bridge actually waiting
// it out -- so it is the only place where the two could disagree about what
// arrives inside one. A test that only checked the ids would have been blind to
// exactly the thing this entry adds.
func exerciseGestures(t *testing.T, harness *testsupport.MCPHarness) {
	t.Helper()

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
		State      *struct {
			SpeechMode string `json:"speechMode"`
		} `json:"state"`
	}
	harness.Call(t, "press_gesture", map[string]any{
		"gestures": []string{scriptedKey},
		"grace_ms": 500,
	}).Decode(t, &pressed)

	ids := make([]string, 0, len(pressed.Pressed))
	for _, press := range pressed.Pressed {
		ids = append(ids, press.Gesture)
	}
	if !slices.Equal(ids, []string{scriptedKey}) {
		t.Errorf("pressed = %v, want the id passed through untouched", ids)
	}
	// The bridge scripts this key to speak, so the window must have caught it --
	// which is the whole collapse, proved across the language boundary.
	if len(pressed.Speech) == 0 {
		t.Fatalf("press_gesture returned no speech for %q; the grace window caught nothing", scriptedKey)
	}
	if pressed.SpeechTo <= pressed.SpeechFrom {
		t.Errorf("window = [%d,%d), want a non-empty range around what was said",
			pressed.SpeechFrom, pressed.SpeechTo)
	}
	// Per-key spans and the aggregate window are the same coordinate space, in
	// both implementations, or a batch's attribution means nothing.
	if pressed.Pressed[0].SpeechFrom != pressed.SpeechFrom || pressed.Pressed[0].SpeechTo != pressed.SpeechTo {
		t.Errorf("the single key's span [%d,%d) does not match the call's window [%d,%d)",
			pressed.Pressed[0].SpeechFrom, pressed.Pressed[0].SpeechTo, pressed.SpeechFrom, pressed.SpeechTo)
	}
	if pressed.Speech[0].Index != pressed.SpeechFrom {
		t.Errorf("first entry sits at index %d, outside the window it was reported in (%d)",
			pressed.Speech[0].Index, pressed.SpeechFrom)
	}
	if pressed.State == nil || pressed.State.SpeechMode == "" {
		t.Errorf("state = %+v, want the reader's modes sampled at the window's close", pressed.State)
	}
}

// exerciseSpeech is the `speech` capability group, and the one place index
// arithmetic crosses the language boundary.
//
// The order matters and is the pattern the tools' own descriptions teach: take
// the next index BEFORE acting, act, then read from that index -- so what comes
// back is exactly what the action produced. If the two implementations disagreed
// about whether an index is inclusive, this would return the wrong lines rather
// than an error, which is precisely the class of bug a shared binding could
// never surface.
func exerciseSpeech(t *testing.T, harness *testsupport.MCPHarness) {
	t.Helper()

	var before struct {
		Index int `json:"index"`
	}
	harness.Call(t, "get_next_speech_index", nil).Decode(t, &before)

	harness.Call(t, "press_gesture", map[string]any{"gestures": []string{scriptedKey}})

	var waited struct {
		Found bool   `json:"found"`
		Index int    `json:"index"`
		Text  string `json:"text"`
	}
	harness.Call(t, "wait_for_speech", map[string]any{
		"text":        secondLine,
		"after_index": before.Index,
		"timeout":     5,
	}).Decode(t, &waited)
	if !waited.Found {
		t.Fatalf("wait_for_speech did not find %q after index %d", secondLine, before.Index)
	}
	if waited.Index < before.Index {
		t.Errorf("wait_for_speech matched at index %d, before the index it was told to start at (%d)",
			waited.Index, before.Index)
	}

	var finished struct {
		Finished bool `json:"finished"`
	}
	harness.Call(t, "wait_for_speech_to_finish", map[string]any{"timeout": 5}).Decode(t, &finished)
	if !finished.Finished {
		t.Error("wait_for_speech_to_finish reported the reader still speaking")
	}

	var captured capturedWindow
	harness.Call(t, "get_speech", map[string]any{"since_index": before.Index}).Decode(t, &captured)
	said := strings.Join(captured.texts(), "\n")
	for _, line := range []string{firstLine, secondLine} {
		if !strings.Contains(said, line) {
			t.Errorf("get_speech since %d = %q, want it to contain %q",
				before.Index, said, line)
		}
	}
	if captured.FromIndex != before.Index {
		t.Errorf("fromIndex = %d, want the index asked for (%d)", captured.FromIndex, before.Index)
	}
	if captured.ToIndex <= captured.FromIndex {
		t.Errorf("range [%d, %d) covers nothing, but two lines were spoken",
			captured.FromIndex, captured.ToIndex)
	}

	// Spec 0028, and this is the tier that matters for it: the stamp is
	// produced by the real Python bridge, crosses a real pipe, and is parsed by
	// the generated Go binding. A field that a Go fake encodes with the same
	// binding it is decoded by would prove nothing about either.
	for _, entry := range captured.Entries {
		if entry.EmittedAt == "" {
			t.Errorf("entry %q crossed the wire without emittedAt", entry.Text)
			continue
		}
		if _, err := time.Parse("2006-01-02 15:04:05.000", entry.EmittedAt); err != nil {
			t.Errorf("emittedAt %q is not the documented format: %v", entry.EmittedAt, err)
		}
	}
	// Spec 0021's list shape, proven across the language boundary: two utterances
	// arrive as two entries rather than one welded string, and each keeps the ring
	// index it occupies. A binding that mapped `entries` wrong -- or reintroduced
	// the join -- fails here and nowhere else.
	if len(captured.Entries) < 2 {
		t.Errorf("entries = %v, want one per utterance rather than a joined blob",
			captured.texts())
	}
	for _, entry := range captured.Entries {
		if entry.Index < before.Index {
			t.Errorf("entry %q carries index %d, before the bookmark %d",
				entry.Text, entry.Index, before.Index)
		}
	}

	var last struct {
		Text  string `json:"text"`
		Index int    `json:"index"`
	}
	harness.Call(t, "get_last_speech", nil).Decode(t, &last)
	if !strings.Contains(last.Text, secondLine) {
		t.Errorf("get_last_speech = %q, want the last line spoken, %q", last.Text, secondLine)
	}
}

// exerciseBraille is the `braille` capability group. Braille has its own index
// space, so it is a separate crossing and not a variation on speech.
func exerciseBraille(t *testing.T, harness *testsupport.MCPHarness) {
	t.Helper()

	var captured capturedWindow
	harness.Call(t, "get_braille", map[string]any{"since_index": 0}).Decode(t, &captured)

	if shown := strings.Join(captured.texts(), "\n"); !strings.Contains(shown, brailleCells) {
		t.Errorf("get_braille = %q, want it to contain %q", shown, brailleCells)
	}
	if captured.ToIndex <= 0 {
		t.Errorf("braille range [%d, %d) covers nothing, but the display had content",
			captured.FromIndex, captured.ToIndex)
	}
	// Braille takes the same entry shape as speech, and this is the only fetch it
	// has -- so a binding that got `entries` right for speech and wrong here would
	// leave braille with no coordinate at all (spec 0021).
	if len(captured.Entries) == 0 {
		t.Error("entries is empty, but the display had content")
	}
}

// exerciseAnnounce is the `announce` capability group -- the one command that
// addresses a human rather than the reader.
//
// This tier is the only place it crosses a real binding into a real
// AnnounceHandler: every other Go-side test puts a fake bridge behind it, and a
// fake encoding with the same generated binding cannot disagree with itself.
func exerciseAnnounce(t *testing.T, harness *testsupport.MCPHarness) {
	t.Helper()

	var spoken struct {
		Announced string `json:"announced"`
	}
	harness.Call(t, "announce", map[string]any{"text": announcedHint}).Decode(t, &spoken)

	if spoken.Announced != announcedHint {
		t.Errorf("announce = %q, want the text echoed back unchanged", spoken.Announced)
	}
}

// exerciseAskUser is the rest of the `interact` group: ask_user, a poll nobody
// answers, and then PROOF THAT THE SESSION IS STILL USABLE.
//
// That last call is what this tier adds. A poll miss is the one ordinary outcome
// that leaves a reply in flight, and the two unit tiers cannot see what that does
// to a real connection: the bridge-side roundtrip has no Go client, and the
// Go-side tool tests have a fake port, so neither ever puts a real client's
// deadline arithmetic against a real bridge's wait. When those two disagreed
// (they did -- `waitForUserReply` is the first waiting command whose contract
// default is not the shared 5 s), the symptom landed on the call AFTER the poll,
// as a lost connection. Hence the announce at the end.
//
// The timeout is short and EXPLICIT on purpose. An omitted one makes the bridge
// wait out its own 30 s default, which is 30 s of wall clock in a gate that
// otherwise runs in eight -- and the budget arithmetic it would exercise is
// pinned for free, on a fake clock, in adapters/bridge's
// TestWaitForUserReplyOutlivesTheBridgesOwnDefault. Nothing answers the prompt
// here (the acknowledgement is an NVDA gesture and there is no NVDA in a headless
// run), so `answered: false` is the expected outcome; the answered path is driven
// where a test can reach the entity, in
// tests/integration/test_wire_session_roundtrip.py.
func exerciseAskUser(t *testing.T, harness *testsupport.MCPHarness) {
	t.Helper()

	var asked struct {
		Ticket string `json:"ticket"`
	}
	harness.Call(t, "ask_user", map[string]any{"prompt": askedPrompt}).Decode(t, &asked)
	if asked.Ticket == "" {
		t.Fatal("ask_user returned no ticket, so there is nothing to poll with")
	}

	var replied struct {
		Answered bool   `json:"answered"`
		Text     string `json:"text"`
	}
	harness.Call(t, "wait_for_user_reply", map[string]any{
		"ticket":  asked.Ticket,
		"timeout": 0.25,
	}).Decode(t, &replied)
	if replied.Answered {
		t.Errorf("answered = true, but nothing acknowledged the prompt in a headless run")
	}

	// The claim this exercise exists for: a poll miss leaves the connection in a
	// state the next command can use. If the response stream had desynchronised,
	// this is where it would surface -- as a lost connection, not as a bad answer.
	var spoken struct {
		Announced string `json:"announced"`
	}
	harness.Call(t, "announce", map[string]any{"text": announcedHint}).Decode(t, &spoken)
	if spoken.Announced != announcedHint {
		t.Errorf("after a poll miss, announce = %q -- the response stream is out of step",
			spoken.Announced)
	}
}

// exerciseTyping is the `typing` capability group. There is no fake focus
// state on the far side to read the text back through (this harness does not
// announce `focus`), so what crosses this tier is what every other exercise
// here proves: that TypeParams.text -- punctuation and a non-ASCII character
// included -- reaches the real Python bridge's typeText handler intact and
// comes back acknowledged, not mangled or rejected by either binding's JSON
// encoding.
func exerciseTyping(t *testing.T, harness *testsupport.MCPHarness) {
	t.Helper()

	var typed struct {
		Typed int `json:"typed"`
	}
	harness.Call(t, "type_text", map[string]any{"text": typedText}).Decode(t, &typed)

	if want := utf8.RuneCountInString(typedText); typed.Typed != want {
		t.Errorf("typed = %d, want %d (the rune count of %q surviving the round trip)",
			typed.Typed, want, typedText)
	}
}

// exerciseStateWrite: the one command whose whole value is a DISTINCTION, driven
// across the language boundary (spec 0033).
//
// Two calls, and the second is the point. The first moves the mode and reports
// `changed: ["browseMode"]`; the second asks for the mode the reader is now in
// and reports `changed: []` -- a success that changed nothing. A binding that
// dropped `changed`, or sent it as null, or let an empty list arrive as a missing
// field, makes those two answers identical, which is exactly the ambiguity the
// command exists to remove. Nothing below the wire can catch that: the Go fake
// and the Go server cannot disagree about a field name.
//
// It also proves the refusal crosses: "none" is reportable and not settable, and
// the bridge's specific reason has to arrive as a specific error rather than a
// bare failure.
func exerciseStateWrite(t *testing.T, harness *testsupport.MCPHarness) {
	t.Helper()

	var written struct {
		State struct {
			BrowseMode string `json:"browseMode"`
		} `json:"state"`
		Changed []string `json:"changed"`
	}

	harness.Call(t, "set_state", map[string]any{"browse_mode": "focus"}).Decode(t, &written)
	if written.State.BrowseMode != "focus" {
		t.Errorf("state after the write = %q, want focus", written.State.BrowseMode)
	}
	if len(written.Changed) != 1 || written.Changed[0] != "browseMode" {
		t.Errorf("changed = %v, want [browseMode] -- the write moved the mode", written.Changed)
	}

	harness.Call(t, "set_state", map[string]any{"browse_mode": "focus"}).Decode(t, &written)
	if written.State.BrowseMode != "focus" {
		t.Errorf("state after the no-op = %q, want focus", written.State.BrowseMode)
	}
	if len(written.Changed) != 0 {
		t.Errorf("changed = %v, want empty -- the reader was already in focus mode", written.Changed)
	}

	// The set-domain is narrower than the get-domain, and the narrowing has to
	// survive the crossing: "none" is a thing get_state REPORTS and set_state
	// must refuse.
	refused := harness.Call(t, "set_state", map[string]any{"browse_mode": "none"})
	if !refused.IsError {
		t.Errorf(`set_state browse_mode:"none" was accepted (%s); it is reportable and not settable`, refused.Text)
	} else if !strings.Contains(refused.Text, "cannot be set") {
		t.Errorf("refusal = %q, want the bridge's own specific reason", refused.Text)
	}
}

// exerciseGuidance: the real Python bridge's own persona document, read through
// the resource the agent actually uses (spec 0029 Part 4).
//
// This is the ONLY tier where the text is genuinely the bridge's: everywhere
// else it comes from a Go fake that could not disagree with the Go server about
// the field names. `getGuidance` is also the one command with no params at all,
// so a binding that got `recognised` or `text` wrong -- or dropped the whole
// result because there was nothing to send -- shows up here and nowhere else.
//
// The phrases asserted on are headings from the ADD-ON's own markdown
// (bridges/nvda/addon/.../documents/), which the harness ships and reads at run
// time. That makes this a packaging check too: a document missing from the tree
// fails here rather than at a live NVDA.
func exerciseGuidance(t *testing.T, harness *testsupport.MCPHarness) {
	t.Helper()

	document := harness.ReadReaderGuidance(t)

	if strings.Contains(document, "{{gestures:") {
		t.Errorf("an unsubstituted gesture marker reached the agent:\n%s", document)
	}

	for _, want := range []string{
		// The server's frame, with the live session substituted into it.
		"nvda's guidance for the `user` stance",
		"the stance wins",
		// The bridge's common section -- the ordinary vocabulary, which no
		// server-owned document could state.
		"The ordinary vocabulary on this reader",
		// A RESOLVED gesture table. The conformance harness stands in for NVDA
		// with a fake resolver whose bindings are deliberately synthetic, so
		// this string could only have arrived by the document asking the reader
		// what is bound -- which is the whole point of the design, and would
		// still pass if the document had hard-coded NVDA's real defaults.
		"`fake+next`",
		// A marker that survived substitution would reach the agent as an
		// unfilled placeholder read as instruction.
		"| What it does | Command | Press |",
		// And the section for the persona this session actually declared.
		"Holding the `user` stance on NVDA",
	} {
		if !strings.Contains(document, want) {
			t.Errorf("the reader guidance never says %q; got:\n%s", want, document)
		}
	}
}

// assertStatusIsProvenOnTheWire: `status` makes a real `ping` round trip while a
// session is live, so a true answer here is the real bridge answering, not this
// server remembering.
func assertStatusIsProvenOnTheWire(t *testing.T, harness *testsupport.MCPHarness) {
	t.Helper()

	var status struct {
		State string `json:"state"`
		Live  *bool  `json:"live"`
	}
	harness.Call(t, "status", nil).Decode(t, &status)

	if status.State != "connected" {
		t.Errorf("status state = %q, want connected", status.State)
	}
	if status.Live == nil || !*status.Live {
		t.Errorf("live = %v, want a ping the real bridge answered", status.Live)
	}
}

// assertInfoDescribesTheSession reads screenreader://info, the other surface the
// handshake's values reach an agent through.
func assertInfoDescribesTheSession(t *testing.T, harness *testsupport.MCPHarness, session connectedSession) {
	t.Helper()

	info := harness.ReadInfo(t)
	if info["reader"] != session.Reader {
		t.Errorf("info reader = %v, want %q", info["reader"], session.Reader)
	}
	if info["readerVersion"] != session.ReaderVersion {
		t.Errorf("info readerVersion = %v, want %q", info["readerVersion"], session.ReaderVersion)
	}
	// The protocol version the BRIDGE reported, which is the one field whose
	// disagreement would have failed the handshake outright.
	if version, ok := info["protocolVersion"].(float64); !ok || version <= 0 {
		t.Errorf("info protocolVersion = %v, want the version the bridge reported", info["protocolVersion"])
	}
}

// assertAdvertises checks tools/list holds everything in `want` and nothing in
// `absent`.
func assertAdvertises(t *testing.T, harness *testsupport.MCPHarness, want, absent []string) {
	t.Helper()

	advertised := harness.ToolNames(t)
	for _, name := range want {
		if !slices.Contains(advertised, name) {
			t.Errorf("tools/list = %v, want it to advertise %q", advertised, name)
		}
	}
	for _, name := range absent {
		if slices.Contains(advertised, name) {
			t.Errorf("tools/list advertises %q, which the reader's capabilities do not permit", name)
		}
	}
}
