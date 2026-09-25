// screenreader-mcp domain -- the status tool's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
package tools_test

import (
	"encoding/json"
	"errors"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

type statusAnswer struct {
	State       string `json:"state"`
	Reason      string `json:"reason"`
	Live        *bool  `json:"live"`
	LiveError   string `json:"liveError"`
	Suppressing *bool  `json:"suppressing"`
	Session     *struct {
		Reader       string   `json:"reader"`
		Endpoint     string   `json:"endpoint"`
		Capabilities []string `json:"capabilities"`
		Mode         string   `json:"mode"`
		LogPath      string   `json:"logPath"`
	} `json:"session"`
}

func runStatus(t *testing.T, call *testsupport.ToolCall) statusAnswer {
	t.Helper()
	result, err := call.Run("")
	if err != nil {
		t.Fatalf("status: %v", err)
	}
	encoded, _ := json.Marshal(result)
	var answer statusAnswer
	if err := json.Unmarshal(encoded, &answer); err != nil {
		t.Fatalf("decoding the result: %v", err)
	}
	return answer
}

func TestAFreshServerReportsDisconnectedAndDialedNothing(t *testing.T) {
	call := testsupport.NewToolCall(&tools.Status{})

	answer := runStatus(t, call)

	if answer.State != "disconnected" {
		t.Errorf("state = %q, want disconnected", answer.State)
	}
	if answer.Session != nil {
		t.Errorf("session = %+v, want none", answer.Session)
	}
	if len(call.Control.Connects()) != 0 {
		t.Error("status dialed something")
	}
}

func TestWithNoSessionThereIsNoRoundTripToReport(t *testing.T) {
	call := testsupport.NewToolCall(&tools.Status{})

	answer := runStatus(t, call)

	if answer.Live != nil {
		t.Errorf("live = %v, want absent when there is no session", *answer.Live)
	}
	if call.Control.Verifies() != 0 {
		t.Error("status pinged with no session to ping")
	}
}

func TestALiveSessionIsProvedByARealRoundTrip(t *testing.T) {
	call := testsupport.NewToolCall(&tools.Status{})
	built := testsupport.NewConnection("nvda", testsupport.EveryCapability()...)
	call.WithConnection(built.Connection)
	call.Control.SetStatus(entities.ConnectionStatus{State: entities.Connected})

	answer := runStatus(t, call)

	if call.Control.Verifies() != 1 {
		t.Errorf("Verify called %d times, want once -- the answer must be proof, "+
			"not possibly-stale local state", call.Control.Verifies())
	}
	if answer.Live == nil || !*answer.Live {
		t.Errorf("live = %v, want true", answer.Live)
	}
	if answer.State != "connected" {
		t.Errorf("state = %q, want connected", answer.State)
	}
	if answer.Session == nil {
		t.Fatal("session = nil, want the live session described")
	}
	if answer.Session.Reader != "nvda" || answer.Session.Endpoint != "local:nvdaMcpBridge" {
		t.Errorf("session = %+v, want the reader and endpoint that answered", *answer.Session)
	}
	if len(answer.Session.Capabilities) != len(testsupport.EveryCapability()) {
		t.Errorf("capabilities = %v, want every capability", answer.Session.Capabilities)
	}
	if answer.Session.LogPath == "" {
		t.Error("session log path must be reported")
	}
}

func TestARoundTripThatFailsReportsTheLossRatherThanFailing(t *testing.T) {
	call := testsupport.NewToolCall(&tools.Status{})
	built := testsupport.NewConnection("nvda", testsupport.EveryCapability()...)
	call.WithConnection(built.Connection)
	call.Control.SetStatus(entities.ConnectionStatus{State: entities.Connected})
	call.Control.FailVerifyWith(ports.ErrConnectionLost)

	answer := runStatus(t, call)

	if answer.Live == nil || *answer.Live {
		t.Errorf("live = %v, want false", answer.Live)
	}
	if answer.LiveError == "" {
		t.Error("liveError is empty; the agent needs to know why the round trip failed")
	}
	if answer.State != "disconnected" {
		t.Errorf("state = %q, want the state Verify corrected it to", answer.State)
	}
	if answer.Session != nil {
		t.Errorf("session = %+v, want none once the loss was recorded", *answer.Session)
	}
}

func TestAnIncompatibleBridgeKeepsBeingReported(t *testing.T) {
	call := testsupport.NewToolCall(&tools.Status{})
	mismatch := &ports.ProtocolMismatchError{BridgeVersion: 2, ServerVersions: []int{1}}
	call.Control.SetStatus(entities.ConnectionStatus{
		State: entities.Incompatible, Reason: mismatch.Error(),
	})

	answer := runStatus(t, call)

	if answer.State != "incompatible" {
		t.Errorf("state = %q, want incompatible", answer.State)
	}
	if answer.Reason == "" {
		t.Error("reason is empty; status must keep saying why")
	}
}

func TestStatusTakesNoParameters(t *testing.T) {
	call := testsupport.NewToolCall(&tools.Status{})

	if _, err := call.Run(""); err != nil {
		t.Errorf("a call with no arguments failed: %v", err)
	}
}

func TestARefusedPingStillLeavesTheSessionDescribed(t *testing.T) {
	call := testsupport.NewToolCall(&tools.Status{})
	built := testsupport.NewConnection("nvda", entities.CapabilitySpeech)
	call.WithConnection(built.Connection)
	call.Control.SetStatus(entities.ConnectionStatus{State: entities.Connected})

	call.Control.FailVerifyWith(errors.New("bridge refused ping: busy"))

	answer := runStatus(t, call)
	if answer.Session == nil {
		t.Error("a refused ping ended the session; only a lost connection should")
	}
	if answer.Live == nil || *answer.Live {
		t.Errorf("live = %v, want false -- the round trip did not succeed", answer.Live)
	}
}

func TestStatusReportsSuppressionOffTheRoundTrip(t *testing.T) {
	call := testsupport.NewToolCall(&tools.Status{})
	built := testsupport.NewConnection("nvda", testsupport.EveryCapability()...)
	call.WithConnection(built.Connection)
	call.Control.SetStatus(entities.ConnectionStatus{State: entities.Connected})
	call.Control.ReportSuppressing(true)

	answer := runStatus(t, call)

	if answer.Suppressing == nil || !*answer.Suppressing {
		t.Errorf("suppressing = %v, want true for a silent session", answer.Suppressing)
	}
}

func TestStatusIsHowALiftIsDiscovered(t *testing.T) {
	call := testsupport.NewToolCall(&tools.Status{})
	built := testsupport.NewConnection("nvda", testsupport.EveryCapability()...)
	call.WithConnection(built.Connection)
	call.Control.SetStatus(entities.ConnectionStatus{State: entities.Connected})
	// The cap has restored speech, and the session is still live.
	call.Control.ReportSuppressing(false)

	answer := runStatus(t, call)

	if answer.Live == nil || !*answer.Live {
		t.Fatalf("live = %v, want a session that is still up", answer.Live)
	}
	if answer.Suppressing == nil || *answer.Suppressing {
		t.Errorf("suppressing = %v, want false after a lift", answer.Suppressing)
	}
}

func TestABridgeThatDoesNotSaySuppressesNothingIntoTheAnswer(t *testing.T) {
	// Absent, not false: an older bridge has said nothing.
	call := testsupport.NewToolCall(&tools.Status{})
	built := testsupport.NewConnection("nvda", testsupport.EveryCapability()...)
	call.WithConnection(built.Connection)
	call.Control.SetStatus(entities.ConnectionStatus{State: entities.Connected})

	answer := runStatus(t, call)

	if answer.Suppressing != nil {
		t.Errorf("suppressing = %v, want absent when the bridge did not say", *answer.Suppressing)
	}
}

func TestAFailedRoundTripReportsNoSuppressionState(t *testing.T) {
	call := testsupport.NewToolCall(&tools.Status{})
	built := testsupport.NewConnection("nvda", testsupport.EveryCapability()...)
	call.WithConnection(built.Connection)
	call.Control.SetStatus(entities.ConnectionStatus{State: entities.Connected})
	call.Control.ReportSuppressing(true)
	call.Control.FailVerifyWith(errors.New("bridge refused ping: busy"))

	answer := runStatus(t, call)

	if answer.Suppressing != nil {
		t.Errorf("suppressing = %v, want absent when the probe failed", *answer.Suppressing)
	}
	if answer.LiveError == "" {
		t.Error("the failure was not reported")
	}
}
