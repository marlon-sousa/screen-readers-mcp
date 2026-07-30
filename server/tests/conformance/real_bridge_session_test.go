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
	"unicode/utf8"

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

// ungatedTools is what a server with no session advertises; gatedTools is what
// this bridge's announced capabilities must add.
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
		"get_next_speech_index",     // speech
		"get_speech",                // speech
		"get_state",                 // state
		"press_gesture",             // gestures
		"set_config",                // config
		"set_log_level",             // log
		"type_text",                 // typing
		"wait_for_speech",           // speech
		"wait_for_speech_to_finish", // speech
		"wait_for_user_reply",       // interact
	}

	unannouncedTools = []string{}
)

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

	assertAdvertises(t, harness, ungatedTools, nil)

	session := connect(t, harness, bridge)
	harness.AwaitToolsChanged(t)
	assertAdvertises(t, harness, append(slices.Clone(ungatedTools), gatedTools...), unannouncedTools)

	exerciseGestures(t, harness)
	exerciseSpeech(t, harness)
	exerciseBraille(t, harness)
	exerciseAnnounce(t, harness)
	exerciseAskUser(t, harness)
	exerciseTyping(t, harness)
	exerciseLog(t, harness)
	assertStatusIsProvenOnTheWire(t, harness)
	assertInfoDescribesTheSession(t, harness, session)

	disconnect(t, harness)
	harness.AwaitToolsChanged(t)
	assertAdvertises(t, harness, ungatedTools, gatedTools)

	// A second session on the same bridge process: `bye` really did tear the
	// first one down, and the bridge went back to accepting. A teardown that
	// only looked clean from this side would fail here.
	connect(t, harness, bridge)
	harness.AwaitToolsChanged(t)
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
	Synth         string   `json:"synth"`
	LogPath       string   `json:"logPath"`
}

// connect performs the handshake and checks that every field the real bridge
// sent survived the crossing.
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

	want := []string{
		"braille", "config", "focus", "gestures",
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

	var slice struct {
		Text            string `json:"text"`
		Entries         int    `json:"entries"`
		Matched         int    `json:"matched"`
		Truncated       bool   `json:"truncated"`
		FromCommandID   int    `json:"fromCommandId"`
		ToCommandID     int    `json:"toCommandId"`
		CapturedAtLevel string `json:"capturedAtLevel"`
	}
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
	// binding forgot to populate.
	if slice.FromCommandID <= 0 || slice.ToCommandID <= 0 {
		t.Errorf("command range = %d..%d, want the ids the bridge actually marked",
			slice.FromCommandID, slice.ToCommandID)
	}
	if slice.FromCommandID > slice.ToCommandID {
		t.Errorf("command range = %d..%d, want it ordered oldest-first",
			slice.FromCommandID, slice.ToCommandID)
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
	var widened struct {
		FromCommandID   int    `json:"fromCommandId"`
		CapturedAtLevel string `json:"capturedAtLevel"`
	}
	harness.Call(t, "get_log", map[string]any{"windows": 2}).Decode(t, &widened)
	if widened.CapturedAtLevel != "info" {
		t.Errorf("capturedAtLevel over two windows = %q, want the info in force before "+
			"set_log_level ran", widened.CapturedAtLevel)
	}
	if widened.FromCommandID >= slice.FromCommandID {
		t.Errorf("two windows started at command %d, want something older than %d",
			widened.FromCommandID, slice.FromCommandID)
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

// exerciseGestures is the `gestures` capability group: opaque reader ids over
// the wire and back.
func exerciseGestures(t *testing.T, harness *testsupport.MCPHarness) {
	t.Helper()

	var pressed struct {
		Pressed []string `json:"pressed"`
	}
	harness.Call(t, "press_gesture", map[string]any{
		"gestures": []string{scriptedKey},
	}).Decode(t, &pressed)

	if !slices.Equal(pressed.Pressed, []string{scriptedKey}) {
		t.Errorf("pressed = %v, want the id passed through untouched", pressed.Pressed)
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

	var captured struct {
		Text      string `json:"text"`
		FromIndex int    `json:"fromIndex"`
		ToIndex   int    `json:"toIndex"`
	}
	harness.Call(t, "get_speech", map[string]any{"since_index": before.Index}).Decode(t, &captured)
	for _, line := range []string{firstLine, secondLine} {
		if !strings.Contains(captured.Text, line) {
			t.Errorf("get_speech since %d = %q, want it to contain %q",
				before.Index, captured.Text, line)
		}
	}
	if captured.FromIndex != before.Index {
		t.Errorf("fromIndex = %d, want the index asked for (%d)", captured.FromIndex, before.Index)
	}
	if captured.ToIndex <= captured.FromIndex {
		t.Errorf("range [%d, %d) covers nothing, but two lines were spoken",
			captured.FromIndex, captured.ToIndex)
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

	var captured struct {
		Text      string `json:"text"`
		FromIndex int    `json:"fromIndex"`
		ToIndex   int    `json:"toIndex"`
	}
	harness.Call(t, "get_braille", map[string]any{"since_index": 0}).Decode(t, &captured)

	if !strings.Contains(captured.Text, brailleCells) {
		t.Errorf("get_braille = %q, want it to contain %q", captured.Text, brailleCells)
	}
	if captured.ToIndex <= 0 {
		t.Errorf("braille range [%d, %d) covers nothing, but the display had content",
			captured.FromIndex, captured.ToIndex)
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
