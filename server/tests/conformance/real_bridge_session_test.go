//go:build conformance

// screenreader-mcp tests -- a whole session against the REAL Python bridge.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: conformance scenario: the built server binary drives a whole session against the real NVDA bridge over
// a real transport.
// Everything but NVDA is real; the harness fakes NVDA at the bridge's AdapterFactory port.
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

// Literals shared with bridges/nvda/tests/support/conformance_bridge.py; keep both sides in step.
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
	typedText     = "café — 50%"
)

var (
	ungatedTools = []string{"connect_reader", "disconnect_reader", "list_readers", "status"}

	gatedTools = []string{
		"announce",                  // interact
		"ask_user",                  // interact
		"get_braille",               // braille
		"get_config",                // config
		"get_document_snapshot",     // document
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

func TestAWholeSessionOverLoopbackTCP(t *testing.T) {
	runWholeSession(t, "tcp")
}

func runWholeSession(t *testing.T, transport string) {
	t.Helper()

	bridge := startPythonBridge(t, transport)
	harness := startServer(t, bridge.Endpoint)

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
	assertAdvertises(t, harness, wholeSurface, unannouncedTools)

	// A second session proves `bye` really tore the first one down and the bridge accepts again.
	connect(t, harness, bridge)
	disconnect(t, harness)
}

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

	ReaderGuidance     string `json:"readerGuidance"`
	ReaderGuidanceText string `json:"readerGuidanceText"`

	SilenceCap string `json:"silenceCap"`
}

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
	if session.Mode != "silent" {
		t.Errorf("mode = %q, want the silent mode hello established", session.Mode)
	}
	if session.Synth != fakeSynth {
		t.Errorf("synth = %q, want %q", session.Synth, fakeSynth)
	}
	if session.LogPath == "" {
		t.Errorf("log path = %q, want it reported", session.LogPath)
	}
	if session.Persona != "user" {
		t.Errorf("persona = %q, want the declared one back", session.Persona)
	}
	if session.Stance != entities.PersonaUser.Stance() {
		t.Errorf("stance = %q, want the persona's stance in full", session.Stance)
	}
	if session.ReaderGuidanceText == "" {
		t.Error("readerGuidanceText is empty; the handshake document did not survive " +
			"the crossing, or the bridge did not send one")
	}
	if strings.Contains(session.ReaderGuidanceText, "{{gestures:") {
		t.Errorf("an unsubstituted gesture marker reached the agent in connect's result:\n%s",
			session.ReaderGuidanceText)
	}
	if session.ReaderGuidance == "" {
		t.Error("readerGuidance is empty; the resource must still be named")
	}

	// The harness declares a human present with no silence cap, the one pair a server that inverts
	// `silenceCap.enabled` to guess attendance gets wrong.
	if strings.Contains(session.SilenceCap, "UNATTENDED") {
		t.Errorf("the real bridge declared a human and the server reported an empty room:\n%s",
			session.SilenceCap)
	}
	if !strings.Contains(session.SilenceCap, "HUMAN IS EXPECTED") {
		t.Errorf("declared attendance did not survive the crossing:\n%s", session.SilenceCap)
	}

	want := []string{
		"braille", "config", "document", "focus", "gestures", "guidance",
		"interact", "log", "speech", "state", "typing",
	}
	got := slices.Clone(session.Capabilities)
	slices.Sort(got)
	if !slices.Equal(got, want) {
		t.Errorf("capabilities = %v, want %v exactly as the real bridge announces them", got, want)
	}
	return session
}

func disconnect(t *testing.T, harness *testsupport.MCPHarness) {
	t.Helper()
	if result := harness.Call(t, "disconnect_reader", nil); result.IsError {
		t.Fatalf("disconnect_reader: %s", result.Text)
	}
}

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

	// get_log does not mark itself, so this press is the command it anchors on.
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
	if slice.Entries != 0 || slice.Matched != 0 || slice.Text != "" {
		t.Errorf("slice = %d/%d %q, want an honest empty answer from a bridge with no NVDA",
			slice.Entries, slice.Matched, slice.Text)
	}

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

	if refused := harness.Call(t, "get_log", map[string]any{
		"fields": []string{"levl"},
	}); !refused.IsError {
		t.Error("get_log accepted an unknown field name instead of refusing it")
	}

	if refused := harness.Call(t, "set_log_level", map[string]any{
		"level": "error",
	}); !refused.IsError {
		t.Error("set_log_level accepted 'error', which would silence the user's own log")
	}
}

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
	if _, err := time.Parse("2006-01-02 15:04:05.000", mark.Time); err != nil {
		t.Errorf("time = %q, want the transcript's own stamp format: %v", mark.Time, err)
	}

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
	if tail.FromCommandID != nil || tail.ToCommandID != nil {
		t.Errorf("a position-anchored read reported command range %v..%v, want none",
			tail.FromCommandID, tail.ToCommandID)
	}

	// Position 0 is the start of the session, not unset.
	if refused := harness.Call(t, "get_log", map[string]any{
		"sincePosition": 0,
	}); refused.IsError {
		t.Errorf("get_log from position 0 was refused: %s", refused.Text)
	}

	if refused := harness.Call(t, "get_log", map[string]any{
		"sincePosition": mark.Position,
		"lastSeconds":   10,
	}); !refused.IsError {
		t.Error("get_log accepted two anchors at once instead of refusing them")
	}

	if timed := harness.Call(t, "get_log", map[string]any{
		"lastSeconds": 30,
	}); timed.IsError {
		t.Errorf("get_log with lastSeconds alone: %s", timed.Text)
	}

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
	if len(pressed.Speech) == 0 {
		t.Fatalf("press_gesture returned no speech for %q; the grace window caught nothing", scriptedKey)
	}
	if pressed.SpeechTo <= pressed.SpeechFrom {
		t.Errorf("window = [%d,%d), want a non-empty range around what was said",
			pressed.SpeechFrom, pressed.SpeechTo)
	}
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

	// firstLine sits exactly at the bookmark, so only it tells an inclusive left edge from an exclusive one.
	var atEdge struct {
		Found bool `json:"found"`
		Index int  `json:"index"`
	}
	harness.Call(t, "wait_for_speech", map[string]any{
		"text":        firstLine,
		"after_index": before.Index,
		"timeout":     5,
	}).Decode(t, &atEdge)
	if !atEdge.Found {
		t.Fatalf("wait_for_speech(after_index=%d) did not find %q, the first line the gesture caused; "+
			"the bridge is treating the left edge as exclusive", before.Index, firstLine)
	}
	if atEdge.Index != before.Index {
		t.Errorf("wait_for_speech matched %q at index %d, want the bookmark itself (%d)",
			firstLine, atEdge.Index, before.Index)
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

	for _, entry := range captured.Entries {
		if entry.EmittedAt == "" {
			t.Errorf("entry %q crossed the wire without emittedAt", entry.Text)
			continue
		}
		if _, err := time.Parse("2006-01-02 15:04:05.000", entry.EmittedAt); err != nil {
			t.Errorf("emittedAt %q is not the documented format: %v", entry.EmittedAt, err)
		}
	}
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
	if len(captured.Entries) == 0 {
		t.Error("entries is empty, but the display had content")
	}
}

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

// The poll's timeout is explicit because the bridge's own default is 30 s.
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

	// A poll miss leaves a reply in flight; a desynchronised stream surfaces here as a lost connection.
	var spoken struct {
		Announced string `json:"announced"`
	}
	harness.Call(t, "announce", map[string]any{"text": announcedHint}).Decode(t, &spoken)
	if spoken.Announced != announcedHint {
		t.Errorf("after a poll miss, announce = %q -- the response stream is out of step",
			spoken.Announced)
	}
}

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

	refused := harness.Call(t, "set_state", map[string]any{"browse_mode": "none"})
	if !refused.IsError {
		t.Errorf(`set_state browse_mode:"none" was accepted (%s); it is reportable and not settable`, refused.Text)
	} else if !strings.Contains(refused.Text, "cannot be set") {
		t.Errorf("refusal = %q, want the bridge's own specific reason", refused.Text)
	}
}

// The phrases are headings in the add-on's own documents, so this also catches a document missing from the tree.
func exerciseGuidance(t *testing.T, harness *testsupport.MCPHarness) {
	t.Helper()

	document := harness.ReadReaderGuidance(t)

	if strings.Contains(document, "{{gestures:") {
		t.Errorf("an unsubstituted gesture marker reached the agent:\n%s", document)
	}

	for _, want := range []string{
		"nvda's guidance for the `user` stance",
		"the stance wins",
		"The ordinary vocabulary on this reader",
		// The harness's resolver has synthetic bindings, so this can only come from the document asking the reader.
		"`fake+next`",
		"| What it does | Command | Press |",
		"Holding the `user` stance on NVDA",
	} {
		if !strings.Contains(document, want) {
			t.Errorf("the reader guidance never says %q; got:\n%s", want, document)
		}
	}
}

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

func assertInfoDescribesTheSession(t *testing.T, harness *testsupport.MCPHarness, session connectedSession) {
	t.Helper()

	info := harness.ReadInfo(t)
	if info["reader"] != session.Reader {
		t.Errorf("info reader = %v, want %q", info["reader"], session.Reader)
	}
	if info["readerVersion"] != session.ReaderVersion {
		t.Errorf("info readerVersion = %v, want %q", info["readerVersion"], session.ReaderVersion)
	}
	if version, ok := info["protocolVersion"].(float64); !ok || version <= 0 {
		t.Errorf("info protocolVersion = %v, want the version the bridge reported", info["protocolVersion"])
	}
}

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
