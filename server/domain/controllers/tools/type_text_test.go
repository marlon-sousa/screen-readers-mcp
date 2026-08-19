// screenreader-mcp domain -- the type_text tool's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// Its own file rather than a line in reader_tools_test.go's opaque-passthrough
// group: the property worth protecting here is different -- text_typer.go is
// exactly how a secret would be entered (spec 0019), so the one thing that must
// never happen is the text landing in the tool's own result.
package tools_test

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

func TestTypeTextSendsTheTextUnchanged(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityTyping)
	call := testsupport.NewToolCall(&tools.TypeText{}).WithConnection(built.Connection)

	var typed struct {
		Typed int `json:"typed"`
	}
	result, err := call.Run(`{"text":"www.blindtec.com.br"}`)
	if err != nil {
		t.Fatalf("type_text: %v", err)
	}
	decode(t, result, &typed)

	sent := built.Text.Typed()
	if len(sent) != 1 || sent[0] != "www.blindtec.com.br" {
		t.Errorf("typed %v, want [%q]", sent, "www.blindtec.com.br")
	}
	if typed.Typed != len("www.blindtec.com.br") {
		t.Errorf("typed count = %d, want %d", typed.Typed, len("www.blindtec.com.br"))
	}
}

// The result must never carry the literal text back -- type_text is exactly
// how a secret would be entered, and the tool result is not the place to leak
// it. Only a count is reported.
func TestTypeTextResultNeverEchoesTheText(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityTyping)
	call := testsupport.NewToolCall(&tools.TypeText{}).WithConnection(built.Connection)

	result, err := call.Run(`{"text":"hunter2"}`)
	if err != nil {
		t.Fatalf("type_text: %v", err)
	}
	// The result must not contain the text in any field, under any name --
	// checked against its serialized JSON so a future field could not smuggle
	// it back in unnoticed.
	encoded, err := json.Marshal(result)
	if err != nil {
		t.Fatalf("marshaling the result: %v", err)
	}
	if strings.Contains(string(encoded), "hunter2") {
		t.Fatalf("the result carries the literal secret: %s", encoded)
	}
	var typed struct {
		Typed int `json:"typed"`
	}
	decode(t, result, &typed)
	if typed.Typed != len("hunter2") {
		t.Errorf("typed count = %d, want %d", typed.Typed, len("hunter2"))
	}
}

// A multi-byte character is one TYPED character, not however many UTF-8 bytes
// it took -- the count is meant to read like a length a human would recognise.
//
// Since spec 0025 the count is the READER's answer, passed through rather than
// recomputed here: the side that injected the characters is the one authority on
// how many there were, and two independent counts of one string is exactly how
// they come to disagree.
func TestTypeTextCountsRunesNotBytes(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityTyping)
	call := testsupport.NewToolCall(&tools.TypeText{}).WithConnection(built.Connection)

	var typed struct {
		Typed int `json:"typed"`
	}
	result, err := call.Run(`{"text":"café — 50%"}`)
	if err != nil {
		t.Fatalf("type_text: %v", err)
	}
	decode(t, result, &typed)

	want := len([]rune("café — 50%"))
	if typed.Typed != want {
		t.Errorf("typed count = %d, want %d runes", typed.Typed, want)
	}
}

// Spec 0025: typing defaults to NO grace, unlike press_gesture. With "speak
// typed characters" on, typing emits one utterance per character and none of
// them is worth a round trip's wait -- but the agent can still ask for one when
// it expects the field itself to announce something.
func TestTypeTextDefaultsToNoGraceAndCarriesOneWhenAsked(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityTyping)
	call := testsupport.NewToolCall(&tools.TypeText{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"text":"ola"}`); err != nil {
		t.Fatalf("type_text: %v", err)
	}
	if _, err := call.Run(`{"text":"ola","grace_ms":300,"announce":"typing the address"}`); err != nil {
		t.Fatalf("type_text: %v", err)
	}

	if graces := built.Text.Graces(); len(graces) != 2 || graces[0] != tools.DefaultTypeGraceMs || graces[1] != 300 {
		t.Errorf("graces = %v, want [%d 300]", graces, tools.DefaultTypeGraceMs)
	}
	if said := built.Text.Announcements(); len(said) != 2 || said[0] != "" || said[1] != "typing the address" {
		t.Errorf("announcements = %q, want nothing then the hint", said)
	}
}

// The same observation shape press_gesture reports, for the same reason: an
// agent should not have to learn two ways to read one answer.
func TestTypeTextReportsTheWindowItObserved(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityTyping)
	built.Text.AnswerWith(ports.TypeOutcome{
		Typed: 3,
		Observation: ports.Observation{
			Speech:    []ports.SpeechEntry{{Text: "ola", Index: 4}},
			FromIndex: 4,
			ToIndex:   5,
			State:     &ports.ReaderState{BrowseMode: "focus", SpeechMode: "talk"},
		},
	})
	call := testsupport.NewToolCall(&tools.TypeText{}).WithConnection(built.Connection)

	result, err := call.Run(`{"text":"ola","grace_ms":200}`)
	if err != nil {
		t.Fatalf("type_text: %v", err)
	}
	var got struct {
		Typed      int `json:"typed"`
		SpeechFrom int `json:"speechFrom"`
		SpeechTo   int `json:"speechTo"`
		Speech     []struct {
			Text string `json:"text"`
		} `json:"speech"`
		State *struct {
			BrowseMode string `json:"browseMode"`
		} `json:"state"`
	}
	decode(t, result, &got)

	if got.Typed != 3 || got.SpeechFrom != 4 || got.SpeechTo != 5 {
		t.Errorf("typed %d over window [%d,%d), want 3 over [4,5)", got.Typed, got.SpeechFrom, got.SpeechTo)
	}
	if len(got.Speech) != 1 || got.Speech[0].Text != "ola" {
		t.Errorf("speech = %v, want what the field said back", got.Speech)
	}
	if got.State == nil || got.State.BrowseMode != "focus" {
		t.Errorf("state = %v, want the modes the agent cannot hear", got.State)
	}
}

func TestTypeTextRequiresText(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityTyping)
	call := testsupport.NewToolCall(&tools.TypeText{}).WithConnection(built.Connection)

	if _, err := call.Run(`{}`); err == nil {
		t.Error("type_text accepted a call with no text")
	}
	if len(built.Text.Typed()) != 0 {
		t.Error("a call with no text reached the reader")
	}
}

// The gate, structurally: a reader that cannot type never announces the
// capability, so the port was never handed over.
func TestTypeTextIsRefusedWhenTheReaderDidNotAnnounceIt(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilitySpeech)
	call := testsupport.NewToolCall(&tools.TypeText{}).WithConnection(built.Connection)

	_, err := call.Run(`{"text":"hello"}`)

	var capability *tools.CapabilityError
	if !errors.As(err, &capability) {
		t.Fatalf("type_text = %v, want a *CapabilityError", err)
	}
	if capability.Capability != entities.CapabilityTyping {
		t.Errorf("Capability = %q, want typing", capability.Capability)
	}
	if capability.Reader != "nvda" {
		t.Errorf("Reader = %q, want the connected reader named", capability.Reader)
	}
}

// A bridge that could not complete the injection (SendInput blocked by another
// thread holding the input desktop) fails the call; the session survives it
// (protocol.md §3), so the tool must surface the error rather than swallow it.
func TestTypeTextSurfacesABridgeFailure(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityTyping)
	call := testsupport.NewToolCall(&tools.TypeText{}).WithConnection(built.Connection)
	built.Text.FailWith(errors.New("SendInput inserted 0 of 1 event"))

	if _, err := call.Run(`{"text":"hello"}`); err == nil {
		t.Error("a failing injection was reported as success")
	}
}
