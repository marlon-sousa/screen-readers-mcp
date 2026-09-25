// screenreader-mcp domain -- the Connection controller's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
package controllers_test

import (
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/fakes"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// harness is the controller with every collaborator faked, plus the fakes themselves.
type harness struct {
	controller *controllers.Connection
	dialer     *fakes.FakeSessionDialer
	clock      *fakes.FakeClock
	log        *fakes.FakeLog
}

func newHarness(t *testing.T, readers ...entities.ConfiguredReader) *harness {
	t.Helper()
	if len(readers) == 0 {
		readers = []entities.ConfiguredReader{
			testsupport.Reader(t, "nvda", "local:nvdaMcpBridge", "tcp:127.0.0.1:8765"),
		}
	}

	built := &harness{
		dialer: fakes.NewFakeSessionDialer(),
		clock:  fakes.NewFakeClock(),
		log:    fakes.NewFakeLog(),
	}
	built.controller = controllers.NewConnection(
		fakes.NewFakeEndpointSource(readers...),
		fakes.NewFakeEndpointProbe(),
		built.dialer,
		built.clock,
		built.log,
	)
	return built
}

// connected scripts a successful dial for a reader announcing these
// capabilities, and returns the connection's fakes.
func (h *harness) connected(reader string, announced ...entities.Capability) *testsupport.Connection {
	built := testsupport.NewConnection(reader, announced...)
	h.dialer.Returns(built.Connection)
	return built
}

func silent() ports.SessionOptions {
	return ports.SessionOptions{Mode: entities.CaptureSilent}
}

func TestAFreshControllerIsDisconnectedAndHasDialedNothing(t *testing.T) {
	h := newHarness(t)

	if state := h.controller.Status().State; state != entities.Disconnected {
		t.Errorf("state = %q, want disconnected", state)
	}
	if h.controller.Current() != nil {
		t.Error("a fresh controller has a connection")
	}
	if len(h.dialer.Calls()) != 0 {
		t.Error("a fresh controller dialed something")
	}
}

func TestConnectingRecordsTheSessionTheBridgeConfirmed(t *testing.T) {
	h := newHarness(t)
	h.connected("nvda", entities.CapabilitySpeech, entities.CapabilityGestures)

	connection, err := h.controller.Connect("nvda", silent())
	if err != nil {
		t.Fatalf("Connect: %v", err)
	}

	if connection.Session.Reader.Name != "nvda" {
		t.Errorf("reader = %q, want nvda", connection.Session.Reader.Name)
	}
	if state := h.controller.Status().State; state != entities.Connected {
		t.Errorf("state = %q, want connected", state)
	}
	if h.controller.Current() != connection {
		t.Error("the connection Connect returned is not the one it recorded")
	}
	if !connection.Session.Capabilities.Has(entities.CapabilitySpeech) {
		t.Error("the announced speech capability did not reach the session")
	}
	if connection.Session.Capabilities.Has(entities.CapabilityBraille) {
		t.Error("a capability the reader never announced reached the session")
	}
}

func TestTheSessionParametersReachTheDialerUnchanged(t *testing.T) {
	h := newHarness(t)
	h.connected("nvda", entities.CapabilitySpeech)
	level := entities.ReaderLogDebug

	_, err := h.controller.Connect("nvda", ports.SessionOptions{
		Mode: entities.CaptureLive, LogLevel: &level,
	})
	if err != nil {
		t.Fatalf("Connect: %v", err)
	}

	calls := h.dialer.Calls()
	if len(calls) != 1 {
		t.Fatalf("dialed %d times, want once", len(calls))
	}
	if calls[0].Options.Mode != entities.CaptureLive {
		t.Errorf("mode = %q, want live", calls[0].Options.Mode)
	}
	if calls[0].Options.LogLevel == nil || *calls[0].Options.LogLevel != entities.ReaderLogDebug {
		t.Errorf("log level = %v, want debug", calls[0].Options.LogLevel)
	}
	if len(calls[0].Reader.Endpoints) != 2 || calls[0].Reader.Endpoints[0].Kind != entities.TransportLocal {
		t.Errorf("endpoints = %v, want both, pipe first", calls[0].Reader.Endpoints)
	}
}

func TestConnectingWhileConnectedIsAnErrorAndLeavesTheSessionAlone(t *testing.T) {
	h := newHarness(t)
	h.connected("nvda", entities.CapabilitySpeech)
	first, err := h.controller.Connect("nvda", silent())
	if err != nil {
		t.Fatalf("Connect: %v", err)
	}

	_, err = h.controller.Connect("nvda", silent())
	if err == nil {
		t.Fatal("a second connect succeeded")
	}
	if h.controller.Current() != first {
		t.Error("the live session was replaced; a second connect must leave it untouched")
	}
	if len(h.dialer.Calls()) != 1 {
		t.Errorf("dialed %d times, want once -- the second connect must not dial",
			len(h.dialer.Calls()))
	}
}

func TestAnUnknownReaderNamesTheOnesThatExist(t *testing.T) {
	h := newHarness(t,
		testsupport.Reader(t, "nvda", "local:nvdaMcpBridge"),
		testsupport.Reader(t, "jaws", "local:jawsMcpBridge"),
	)

	_, err := h.controller.Connect("narrator", silent())
	if err == nil {
		t.Fatal("connecting to an unknown reader succeeded")
	}
	if !strings.Contains(err.Error(), "nvda") || !strings.Contains(err.Error(), "jaws") {
		t.Errorf("error = %q, want the known readers listed", err)
	}
	if len(h.dialer.Calls()) != 0 {
		t.Error("an unknown reader was dialed")
	}
}

func TestAProtocolMismatchIsRecordedAsIncompatible(t *testing.T) {
	h := newHarness(t)
	h.dialer.FailWith(&ports.ProtocolMismatchError{BridgeVersion: 2, ServerVersions: []int{1}})

	_, err := h.controller.Connect("nvda", silent())
	if err == nil {
		t.Fatal("a protocol mismatch was reported as success")
	}

	status := h.controller.Status()
	if status.State != entities.Incompatible {
		t.Errorf("state = %q, want incompatible -- the remedy is to update one of "+
			"the two components, not to try again", status.State)
	}
	if !strings.Contains(status.Reason, "2") || !strings.Contains(status.Reason, "1") {
		t.Errorf("reason = %q, want both versions named", status.Reason)
	}
	if h.controller.Current() != nil {
		t.Error("a session was recorded for a handshake that never completed")
	}
}

func TestAFailedConnectIsDisconnectedWithAReasonAndNoRetry(t *testing.T) {
	h := newHarness(t)
	h.dialer.FailWith(errors.New(`reader "nvda": no endpoint answered`))

	if _, err := h.controller.Connect("nvda", silent()); err == nil {
		t.Fatal("a failed connect was reported as success")
	}

	status := h.controller.Status()
	if status.State != entities.Disconnected {
		t.Errorf("state = %q, want disconnected", status.State)
	}
	if status.Reason == "" {
		t.Error("reason is empty; the agent has to be told why")
	}
	if len(h.dialer.Calls()) != 1 {
		t.Errorf("dialed %d times, want once -- there is no retry policy here",
			len(h.dialer.Calls()))
	}
}

func TestDisconnectingSendsByeAndRetractsTheGatedTools(t *testing.T) {
	h := newHarness(t)
	built := h.connected("nvda", entities.CapabilitySpeech, entities.CapabilityBraille)
	if _, err := h.controller.Connect("nvda", silent()); err != nil {
		t.Fatalf("Connect: %v", err)
	}

	if err := h.controller.Disconnect(); err != nil {
		t.Fatalf("Disconnect: %v", err)
	}

	if built.Lifecycle.Byes() != 1 {
		t.Errorf("bye sent %d times, want once", built.Lifecycle.Byes())
	}
	if built.Lifecycle.Closes() != 1 {
		t.Errorf("closed %d times, want once", built.Lifecycle.Closes())
	}
	if h.controller.Current() != nil {
		t.Error("a session survived its own disconnect")
	}
	if state := h.controller.Status().State; state != entities.Disconnected {
		t.Errorf("state = %q, want disconnected", state)
	}
}

func TestDisconnectingWithNoSessionIsHarmless(t *testing.T) {
	h := newHarness(t)

	if err := h.controller.Disconnect(); err != nil {
		t.Errorf("Disconnect with no session: %v", err)
	}
}

func TestDisconnectingAnAlreadyDeadBridgeStillSucceeds(t *testing.T) {
	h := newHarness(t)
	built := h.connected("nvda", entities.CapabilitySpeech)
	if _, err := h.controller.Connect("nvda", silent()); err != nil {
		t.Fatalf("Connect: %v", err)
	}
	built.Lifecycle.FailByeWith(ports.ErrConnectionLost)

	if err := h.controller.Disconnect(); err != nil {
		t.Errorf("Disconnect: %v, want a clean disconnect anyway", err)
	}
	if h.controller.Current() != nil {
		t.Error("a session survived a disconnect its bridge could not acknowledge")
	}
}

func TestAnObservedLossEndsTheSessionAndSaysWhy(t *testing.T) {
	h := newHarness(t)
	built := h.connected("nvda", entities.CapabilitySpeech)
	if _, err := h.controller.Connect("nvda", silent()); err != nil {
		t.Fatalf("Connect: %v", err)
	}
	built.Lifecycle.FailPingWith(ports.ErrConnectionLost)

	if _, err := h.controller.Verify(); !errors.Is(err, ports.ErrConnectionLost) {
		t.Fatalf("Verify = %v, want the loss reported", err)
	}

	if h.controller.Current() != nil {
		t.Error("the connection survived a loss")
	}
	status := h.controller.Status()
	if status.State != entities.Disconnected {
		t.Errorf("state = %q, want disconnected", status.State)
	}
	if !strings.Contains(status.Reason, "lost") {
		t.Errorf("reason = %q, want it to say the connection was lost", status.Reason)
	}
}

func TestARefusedPingLeavesTheSessionStanding(t *testing.T) {
	h := newHarness(t)
	built := h.connected("nvda", entities.CapabilitySpeech)
	if _, err := h.controller.Connect("nvda", silent()); err != nil {
		t.Fatalf("Connect: %v", err)
	}
	built.Lifecycle.FailPingWith(errors.New("bridge refused ping: busy"))

	if _, err := h.controller.Verify(); err == nil {
		t.Fatal("the refusal was not reported")
	}

	if h.controller.Current() == nil {
		t.Error("a refusal ended the session; only a lost connection should")
	}
}

func TestVerifyingWithNoSessionIsNotAFailure(t *testing.T) {
	h := newHarness(t)

	if _, err := h.controller.Verify(); err != nil {
		t.Errorf("Verify with no session = %v, want nil", err)
	}
}

func TestReconnectingAfterALossOpensAFreshSession(t *testing.T) {
	h := newHarness(t)
	built := h.connected("nvda", entities.CapabilitySpeech)
	if _, err := h.controller.Connect("nvda", silent()); err != nil {
		t.Fatalf("Connect: %v", err)
	}
	built.Lifecycle.FailPingWith(ports.ErrConnectionLost)
	_, _ = h.controller.Verify()

	h.connected("nvda", entities.CapabilitySpeech, entities.CapabilityBraille)
	if _, err := h.controller.Connect("nvda", silent()); err != nil {
		t.Fatalf("reconnecting: %v", err)
	}

	current := h.controller.Current()
	if current == nil {
		t.Fatal("reconnecting left no session")
	}
	if !current.Session.Capabilities.Has(entities.CapabilityBraille) {
		t.Error("the reconnected session did not pick up the newly announced braille")
	}
	if state := h.controller.Status().State; state != entities.Connected {
		t.Errorf("state = %q, want connected", state)
	}
}

func TestListJoinsTheConfiguredReadersWithTheProbe(t *testing.T) {
	pipe := testsupport.Endpoint(t, "local:nvdaMcpBridge")
	reader := testsupport.Reader(t, "nvda", "local:nvdaMcpBridge", "tcp:127.0.0.1:8765")

	controller := controllers.NewConnection(
		fakes.NewFakeEndpointSource(reader),
		fakes.NewFakeEndpointProbe(pipe),
		fakes.NewFakeSessionDialer(),
		fakes.NewFakeClock(),
		fakes.NewFakeLog(),
	)

	listing := controller.List()

	if len(listing.Readers) != 1 || len(listing.Readers[0].Endpoints) != 2 {
		t.Fatalf("listing = %+v, want the one reader with both endpoints", listing)
	}
	if listing.Readers[0].Endpoints[0].Liveness != entities.Listening {
		t.Errorf("pipe = %q, want listening", listing.Readers[0].Endpoints[0].Liveness)
	}
	if listing.Readers[0].Endpoints[1].Liveness != entities.LivenessUnknown {
		t.Errorf("tcp = %q, want unknown", listing.Readers[0].Endpoints[1].Liveness)
	}
}

func TestTheHeartbeatProvesTheConnectionOnASchedule(t *testing.T) {
	h := newHarness(t)
	built := h.connected("nvda", entities.CapabilitySpeech)
	if _, err := h.controller.Connect("nvda", silent()); err != nil {
		t.Fatalf("Connect: %v", err)
	}

	// The loop re-checks stop after waking, so stopping inside the third sleep produces no third ping.
	stop := make(chan struct{})
	sleeps := 0
	h.clock.OnSleep(func(d time.Duration) {
		if d != controllers.HeartbeatInterval {
			t.Errorf("slept %s, want the heartbeat interval %s", d, controllers.HeartbeatInterval)
		}
		sleeps++
		if sleeps == 3 {
			close(stop)
		}
	})

	h.controller.RunHeartbeat(stop)

	if built.Lifecycle.Pings() != 2 {
		t.Errorf("pinged %d times over three waits, want 2", built.Lifecycle.Pings())
	}
}

func TestTheHeartbeatRetractsTheToolsWhenTheConnectionHasDied(t *testing.T) {
	h := newHarness(t)
	built := h.connected("nvda", entities.CapabilitySpeech)
	if _, err := h.controller.Connect("nvda", silent()); err != nil {
		t.Fatalf("Connect: %v", err)
	}
	built.Lifecycle.FailPingWith(ports.ErrConnectionLost)

	stop := make(chan struct{})
	sleeps := 0
	h.clock.OnSleep(func(time.Duration) {
		sleeps++
		if sleeps == 2 {
			close(stop)
		}
	})

	h.controller.RunHeartbeat(stop)

	if h.controller.Current() != nil {
		t.Error("the dead connection is still recorded as live")
	}
}

func TestTheHeartbeatIsHarmlessWithNoSession(t *testing.T) {
	h := newHarness(t)

	stop := make(chan struct{})
	h.clock.OnSleep(func(time.Duration) { close(stop) })

	h.controller.RunHeartbeat(stop)

	if len(h.dialer.Calls()) != 0 {
		t.Error("the heartbeat dialed something; only the agent connects")
	}
}

func TestClosingTheControllerEndsALiveSession(t *testing.T) {
	h := newHarness(t)
	built := h.connected("nvda", entities.CapabilitySpeech)
	if _, err := h.controller.Connect("nvda", silent()); err != nil {
		t.Fatalf("Connect: %v", err)
	}

	h.controller.Close()

	if built.Lifecycle.Byes() != 1 {
		t.Errorf("bye sent %d times on shutdown, want once", built.Lifecycle.Byes())
	}
}
