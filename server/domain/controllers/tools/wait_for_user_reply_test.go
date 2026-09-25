// screenreader-mcp domain -- the wait_for_user_reply tool's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
package tools_test

import (
	"errors"
	"testing"
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

func TestWaitForUserReplyReturnsTheAnswer(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityInteract)
	built.Interact.Replies["ticket-1"] = ports.UserReply{Answered: true, Text: "done"}
	call := testsupport.NewToolCall(&tools.WaitForUserReply{}).WithConnection(built.Connection)

	var reply struct {
		Answered bool   `json:"answered"`
		Text     string `json:"text"`
	}
	result, err := call.Run(`{"ticket":"ticket-1","timeout":10}`)
	if err != nil {
		t.Fatalf("wait_for_user_reply: %v", err)
	}
	decode(t, result, &reply)

	if !reply.Answered {
		t.Error("answered = false, want the scripted answer through")
	}
	if reply.Text != "done" {
		t.Errorf("text = %q, want the answer text through", reply.Text)
	}
}

func TestWaitForUserReplyReportsAPollMissWithoutFailing(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityInteract)
	call := testsupport.NewToolCall(&tools.WaitForUserReply{}).WithConnection(built.Connection)

	var reply struct {
		Answered bool `json:"answered"`
	}
	result, err := call.Run(`{"ticket":"ticket-nobody-answered","timeout":1}`)
	if err != nil {
		t.Fatalf("a poll miss was reported as an error: %v", err)
	}
	decode(t, result, &reply)
	if reply.Answered {
		t.Error("answered = true, want false for a poll nobody answered")
	}
}

func TestWaitForUserReplyFillsTheDefaultTimeout(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityInteract)
	call := testsupport.NewToolCall(&tools.WaitForUserReply{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"ticket":"ticket-1"}`); err != nil {
		t.Fatalf("wait_for_user_reply: %v", err)
	}

	polls := built.Interact.Polls()
	if len(polls) != 1 {
		t.Fatalf("polls = %v, want exactly one", polls)
	}
	if polls[0] != 30*time.Second {
		t.Errorf("poll timeout = %v, want the 30 s default filled in", polls[0])
	}
}

func TestWaitForUserReplyCapsAnExcessiveTimeout(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityInteract)
	call := testsupport.NewToolCall(&tools.WaitForUserReply{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"ticket":"ticket-1","timeout":300}`); err != nil {
		t.Fatalf("wait_for_user_reply: %v", err)
	}

	polls := built.Interact.Polls()
	if len(polls) != 1 {
		t.Fatalf("polls = %v, want exactly one", polls)
	}
	if polls[0] != 110*time.Second {
		t.Errorf("poll timeout = %v, want it capped at 110 s", polls[0])
	}
}

func TestWaitForUserReplyPassesAReasonableTimeoutThrough(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityInteract)
	call := testsupport.NewToolCall(&tools.WaitForUserReply{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"ticket":"ticket-1","timeout":45}`); err != nil {
		t.Fatalf("wait_for_user_reply: %v", err)
	}

	polls := built.Interact.Polls()
	if len(polls) != 1 || polls[0] != 45*time.Second {
		t.Errorf("polls = %v, want a single 45 s poll", polls)
	}
}

func TestWaitForUserReplyIsRefusedWhenTheReaderDidNotAnnounceInteract(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilitySpeech)
	call := testsupport.NewToolCall(&tools.WaitForUserReply{}).WithConnection(built.Connection)

	_, err := call.Run(`{"ticket":"ticket-1"}`)

	var capability *tools.CapabilityError
	if !asCapabilityError(err, &capability) {
		t.Fatalf("wait_for_user_reply = %v, want a *CapabilityError", err)
	}
	if capability.Capability != entities.CapabilityInteract {
		t.Errorf("Capability = %q, want interact", capability.Capability)
	}
}

func TestWaitForUserReplySurfacesABridgeFailure(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityInteract)
	call := testsupport.NewToolCall(&tools.WaitForUserReply{}).WithConnection(built.Connection)
	built.Interact.FailWith(errors.New("no outstanding prompt with ticket 'ticket-1'"))

	if _, err := call.Run(`{"ticket":"ticket-1"}`); err == nil {
		t.Error("an expired ticket was reported as success")
	}
}
