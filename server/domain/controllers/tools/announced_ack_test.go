// screenreader-mcp domain -- the announcement acknowledgement, for both tools.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// press_gesture and type_text are tested together because the property is that they answer a narration identically.
package tools_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

func TestAMutatingCallEchoesTheAnnouncementItMade(t *testing.T) {
	const narration = "walking the headings"

	gestures := testsupport.NewConnection("nvda", entities.CapabilityGestures)
	press, err := testsupport.NewToolCall(&tools.PressGesture{}).
		WithConnection(gestures.Connection).
		Run(`{"gestures":["h"],"announce":"` + narration + `"}`)
	if err != nil {
		t.Fatalf("press_gesture: %v", err)
	}
	assertAnnounced(t, "press_gesture", press, narration)
	if said := gestures.Gestures.Announcements(); len(said) != 1 || said[0] != narration {
		t.Errorf("press_gesture carried %q to the reader, want the narration", said)
	}

	typing := testsupport.NewConnection("nvda", entities.CapabilityTyping)
	typed, err := testsupport.NewToolCall(&tools.TypeText{}).
		WithConnection(typing.Connection).
		Run(`{"text":"acter","announce":"` + narration + `"}`)
	if err != nil {
		t.Fatalf("type_text: %v", err)
	}
	assertAnnounced(t, "type_text", typed, narration)
	if said := typing.Text.Announcements(); len(said) != 1 || said[0] != narration {
		t.Errorf("type_text carried %q to the reader, want the narration", said)
	}
}

func TestAMutatingCallOmitsTheAckWhenNothingWasAnnounced(t *testing.T) {
	gestures := testsupport.NewConnection("nvda", entities.CapabilityGestures)
	press, err := testsupport.NewToolCall(&tools.PressGesture{}).
		WithConnection(gestures.Connection).
		Run(`{"gestures":["h"]}`)
	if err != nil {
		t.Fatalf("press_gesture: %v", err)
	}
	assertNoAck(t, "press_gesture", press)

	typing := testsupport.NewConnection("nvda", entities.CapabilityTyping)
	typed, err := testsupport.NewToolCall(&tools.TypeText{}).
		WithConnection(typing.Connection).
		Run(`{"text":"acter"}`)
	if err != nil {
		t.Fatalf("type_text: %v", err)
	}
	assertNoAck(t, "type_text", typed)
}

func TestAWhitespaceOnlyAnnouncementIsRefusedBeforeAnythingHappens(t *testing.T) {
	gestures := testsupport.NewConnection("nvda", entities.CapabilityGestures)
	if _, err := testsupport.NewToolCall(&tools.PressGesture{}).
		WithConnection(gestures.Connection).
		Run(`{"gestures":["h"],"announce":"   "}`); err == nil {
		t.Error("press_gesture accepted a whitespace-only announcement")
	}
	if pressed := gestures.Gestures.Pressed(); len(pressed) != 0 {
		t.Errorf("the keys went out anyway: %v -- a narration that cannot be spoken must be caught before the machine moves", pressed)
	}

	typing := testsupport.NewConnection("nvda", entities.CapabilityTyping)
	if _, err := testsupport.NewToolCall(&tools.TypeText{}).
		WithConnection(typing.Connection).
		Run(`{"text":"acter","announce":"\t"}`); err == nil {
		t.Error("type_text accepted a whitespace-only announcement")
	}
	if typed := typing.Text.Typed(); len(typed) != 0 {
		t.Errorf("the text went in anyway: %v", typed)
	}
}

// Empty, unlike whitespace, is the wire contract's spelling of "say nothing".
func TestAnEmptyAnnouncementIsSilenceRatherThanAnError(t *testing.T) {
	gestures := testsupport.NewConnection("nvda", entities.CapabilityGestures)
	if _, err := testsupport.NewToolCall(&tools.PressGesture{}).
		WithConnection(gestures.Connection).
		Run(`{"gestures":["h"],"announce":""}`); err != nil {
		t.Fatalf("press_gesture refused an empty announcement: %v", err)
	}
	if said := gestures.Gestures.Announcements(); len(said) != 1 || said[0] != "" {
		t.Errorf("announcements = %q, want one call that announced nothing", said)
	}
}

func assertAnnounced(t *testing.T, tool string, result any, want string) {
	t.Helper()
	var ack struct {
		Announced string `json:"announced"`
	}
	decode(t, result, &ack)
	if ack.Announced != want {
		t.Errorf("%s announced = %q, want %q echoed back", tool, ack.Announced, want)
	}
}

// Checked against the serialized JSON because an empty string and an absent one decode identically.
func assertNoAck(t *testing.T, tool string, result any) {
	t.Helper()
	encoded, err := json.Marshal(result)
	if err != nil {
		t.Fatalf("marshaling %s's result: %v", tool, err)
	}
	if strings.Contains(string(encoded), "announced") {
		t.Errorf("%s result carries an ack for an announcement nobody asked for: %s", tool, encoded)
	}
}
