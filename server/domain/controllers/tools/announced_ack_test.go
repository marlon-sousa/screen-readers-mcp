// screenreader-mcp domain -- the announcement acknowledgement, for both tools.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// Its own file, covering press_gesture AND type_text together, for the same
// reason observation.go declares their shared result half once: the property
// under test is that the two answer a narration IDENTICALLY. Split across
// reader_tools_test.go and type_text_test.go it would be two tests that could
// drift, which is the shape of the defect board entry 11.24(b) came from -- an
// announcement that travelled and was never reported back.
package tools_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// The ack an agent narrating to a mute human was missing: it can now confirm
// the announcement was made rather than assume it (board entry 11.24(b), from
// the second external run's ask 3).
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
	// The echo is only honest if the text actually went to the reader. A server
	// that echoed its own parameter without dispatching it would be exactly the
	// false confirmation this entry set out to remove.
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

// Absent means "you did not narrate", which an agent must be able to tell from
// "your narration vanished". They stay distinguishable only while the field is
// omitted rather than sent empty.
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

// An agent that MEANT to narrate and sent whitespace used to get silence and no
// signal: the bridge's own strip() dropped it and nothing reported the loss.
// The announce tool has always refused it; these two now refuse it identically,
// and refuse it BEFORE the machine moves.
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

// Empty is NOT whitespace: it is the wire contract's own spelling of "say
// nothing", and an erased parameter cannot tell it from an absent one.
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

// Checked against the serialized JSON rather than a decoded field: an empty
// string and an absent one decode identically, and absence is the whole claim.
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
