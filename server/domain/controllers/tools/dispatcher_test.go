// screenreader-mcp domain -- the Dispatcher's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// The dispatcher's own behaviour is small, and one part of it carries weight: a
// tool call is usually how a dead connection is discovered FIRST, long before the
// next heartbeat, so the loss has to reach the controller from here or the gated
// tools stay advertised for a reader that is gone.
package tools_test

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/fakes"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// scriptedTool is a tool that fails however a test tells it to.
//
// A stand-in rather than a real gated tool on purpose: what is under test is
// what the DISPATCHER does with a failure, so the failure should be stated
// outright instead of arranged through whichever real tool happens to reach the
// path.
type scriptedTool struct {
	err error
}

func (s *scriptedTool) Name() string                    { return "scripted" }
func (s *scriptedTool) Capability() entities.Capability { return entities.CapabilityGestures }
func (s *scriptedTool) Description() string             { return "a tool that fails on demand" }
func (s *scriptedTool) InputSchema() json.RawMessage    { return json.RawMessage(`{"type":"object"}`) }
func (s *scriptedTool) OutputSchema() json.RawMessage   { return json.RawMessage(`{"type":"object"}`) }

func (s *scriptedTool) Execute(tools.ToolContext, json.RawMessage) (any, error) {
	if s.err != nil {
		return nil, s.err
	}
	return map[string]any{"ok": true}, nil
}

func dispatcherOver(control tools.ConnectionControl, list ...tools.Tool) *tools.Dispatcher {
	return tools.NewDispatcher(
		tools.NewRegistry(list...), control, fakes.NewFakeClock(), fakes.NewFakeLog(), nil,
	)
}

func TestDispatchRunsTheNamedTool(t *testing.T) {
	control := fakes.NewFakeConnectionControl()
	control.SetListing(entities.BuildListing(
		[]entities.ConfiguredReader{{Name: "nvda"}}, nil,
	))
	dispatch := tools.NewDispatcher(
		tools.BuildRegistry(), control, fakes.NewFakeClock(), fakes.NewFakeLog(), nil,
	)

	result, err := dispatch.Execute("list_readers", nil)
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if result == nil {
		t.Fatal("Execute returned no result")
	}
}

// Unreachable through the MCP adapter, which only dispatches names it took from
// the registry -- so reaching it means the wiring is wrong, not the agent.
func TestAnUnknownToolNameIsRejected(t *testing.T) {
	dispatch := dispatcherOver(fakes.NewFakeConnectionControl())

	_, err := dispatch.Execute("nonsense", nil)
	if !errors.Is(err, tools.ErrUnknownTool) {
		t.Errorf("Execute(nonsense) = %v, want ErrUnknownTool", err)
	}
}

// The context is built FRESH per call from the controller's current connection,
// so a tool can never be handed a session that ended between tools/list and now.
func TestTheContextCarriesTheControllersCurrentConnection(t *testing.T) {
	control := fakes.NewFakeConnectionControl()
	built := testsupport.NewConnection("nvda", entities.CapabilityGestures)
	control.SetConnection(built.Connection)

	tool := &scriptedTool{}
	if _, err := dispatcherOver(control, tool).Execute(tool.Name(), nil); err != nil {
		t.Fatalf("Execute: %v", err)
	}

	// With the connection dropped, the very same dispatcher must build a
	// context with no session -- proving the context is not captured once.
	if err := control.Disconnect(); err != nil {
		t.Fatalf("Disconnect: %v", err)
	}
	tool.err = &tools.CapabilityError{Tool: tool.Name(), Capability: entities.CapabilityGestures}
	if _, err := dispatcherOver(control, tool).Execute(tool.Name(), nil); err == nil {
		t.Error("the tool succeeded with no session")
	}
}

// The rule this controller exists for.
func TestALostConnectionSeenByAToolIsReportedToTheController(t *testing.T) {
	control := fakes.NewFakeConnectionControl()
	built := testsupport.NewConnection("nvda", entities.CapabilityGestures)
	control.SetConnection(built.Connection)

	tool := &scriptedTool{err: fmt.Errorf("pressGesture: %w", ports.ErrConnectionLost)}
	_, err := dispatcherOver(control, tool).Execute(tool.Name(), nil)

	if !errors.Is(err, ports.ErrConnectionLost) {
		t.Fatalf("Execute = %v, want the loss reported to the caller too", err)
	}
	if control.Verifies() != 1 {
		t.Errorf("the controller was told about the loss %d times, want once: "+
			"until it is told, the gated tools stay advertised for a reader that is gone",
			control.Verifies())
	}
}

// An ordinary refusal by a HEALTHY bridge must tear nothing down: protocol.md §3
// says an established session survives a failing command.
func TestAnOrdinaryToolFailureDoesNotReCheckTheConnection(t *testing.T) {
	control := fakes.NewFakeConnectionControl()
	built := testsupport.NewConnection("nvda", entities.CapabilityGestures)
	control.SetConnection(built.Connection)

	tool := &scriptedTool{err: errors.New("bridge refused pressGesture: unknown gesture id")}
	if _, err := dispatcherOver(control, tool).Execute(tool.Name(), nil); err == nil {
		t.Fatal("the refusal was not reported")
	}

	if control.Verifies() != 0 {
		t.Error("an ordinary refusal cost a ping round trip; only a lost " +
			"connection should trigger one")
	}
}

// -- the server's own session record (spec 0021) -------------------------------
//
// The dispatcher is the SINGLE route from an MCP request to a tool, which is
// exactly why the record is written here: it sees every call by construction,
// rather than by fifteen tools each remembering to report themselves. Nothing is
// asked of the bridge to build it -- the traffic already passes through here.

func recordingDispatcher(control tools.ConnectionControl, list ...tools.Tool) *tools.Dispatcher {
	return tools.NewDispatcher(
		tools.NewRegistry(list...), control, fakes.NewFakeClock(), fakes.NewFakeLog(),
		entities.NewSessionRecord(),
	)
}

func TestEveryDispatchedCallLandsInTheSessionRecord(t *testing.T) {
	control := fakes.NewFakeConnectionControl()
	built := testsupport.NewConnection("nvda", entities.CapabilityGestures)
	control.SetConnection(built.Connection)
	tool := &scriptedTool{}
	dispatch := recordingDispatcher(control, tool)

	for i := 0; i < 3; i++ {
		if _, err := dispatch.Execute(tool.Name(), json.RawMessage(`{"n":1}`)); err != nil {
			t.Fatalf("Execute: %v", err)
		}
	}

	calls := dispatch.Record().Calls()
	if len(calls) != 3 {
		t.Fatalf("recorded %d calls, want all three", len(calls))
	}
	for _, call := range calls {
		if call.Tool != tool.Name() || call.Failed {
			t.Errorf("recorded %+v, want a successful scripted call", call)
		}
	}
}

// What the agent asked and what it was told is the whole point: a record of bare
// tool names would not let anyone reconstruct a debugging session.
func TestTheRecordKeepsTheParametersAndTheAnswer(t *testing.T) {
	control := fakes.NewFakeConnectionControl()
	built := testsupport.NewConnection("nvda", entities.CapabilityGestures)
	control.SetConnection(built.Connection)
	tool := &scriptedTool{}
	dispatch := recordingDispatcher(control, tool)

	if _, err := dispatch.Execute(tool.Name(), json.RawMessage(`{"gestures":["kb:tab"]}`)); err != nil {
		t.Fatalf("Execute: %v", err)
	}

	call := dispatch.Record().Calls()[0]
	if !strings.Contains(call.Params, "kb:tab") {
		t.Errorf("params = %q, want what the agent actually sent", call.Params)
	}
	if !strings.Contains(call.Result, "ok") {
		t.Errorf("result = %q, want what the tool actually answered", call.Result)
	}
}

// A failed call is frequently the most interesting line in the record, and one
// that vanished would leave an unexplained gap between two successes.
func TestAFailedCallIsRecordedWithItsError(t *testing.T) {
	control := fakes.NewFakeConnectionControl()
	built := testsupport.NewConnection("nvda", entities.CapabilityGestures)
	control.SetConnection(built.Connection)
	tool := &scriptedTool{err: errors.New("bridge refused pressGesture: unknown gesture id")}
	dispatch := recordingDispatcher(control, tool)

	if _, err := dispatch.Execute(tool.Name(), nil); err == nil {
		t.Fatal("the refusal was not reported")
	}

	calls := dispatch.Record().Calls()
	if len(calls) != 1 {
		t.Fatalf("recorded %d calls, want the failure to be one of them", len(calls))
	}
	if !calls[0].Failed || !strings.Contains(calls[0].Error, "unknown gesture id") {
		t.Errorf("recorded %+v, want the failure and its reason", calls[0])
	}
}

// A whole session, end to end, from traffic alone: connect, work, disconnect --
// with no call added to the bridge to keep the record, which is the deliverable.
func TestTheRecordCoversAWholeSessionFromTrafficAlone(t *testing.T) {
	control := fakes.NewFakeConnectionControl()
	built := testsupport.NewConnection("nvda", entities.CapabilityGestures)
	control.SetConnection(built.Connection)
	control.SetListing(entities.BuildListing([]entities.ConfiguredReader{{Name: "nvda"}}, nil))
	dispatch := tools.NewDispatcher(
		tools.BuildRegistry(), control, fakes.NewFakeClock(), fakes.NewFakeLog(),
		entities.NewSessionRecord(),
	)

	for _, step := range []struct {
		tool   string
		params string
	}{
		{"list_readers", `{}`},
		{"press_gesture", `{"gestures":["kb:tab"]}`},
		{"status", `{}`},
	} {
		if _, err := dispatch.Execute(step.tool, json.RawMessage(step.params)); err != nil {
			t.Fatalf("%s: %v", step.tool, err)
		}
	}

	var names []string
	for _, call := range dispatch.Record().Calls() {
		names = append(names, call.Tool)
	}
	want := "list_readers,press_gesture,status"
	if strings.Join(names, ",") != want {
		t.Errorf("record = %v, want the whole sequence %q", names, want)
	}
}

// An unknown tool never runs, so it never happened as far as the session goes --
// recording it would put a line in the history for something the reader never saw.
func TestAnUnknownToolIsNotRecordedAsACall(t *testing.T) {
	control := fakes.NewFakeConnectionControl()
	dispatch := recordingDispatcher(control)

	if _, err := dispatch.Execute("frobnicate", nil); err == nil {
		t.Fatal("an unknown tool was dispatched")
	}

	if got := len(dispatch.Record().Calls()); got != 0 {
		t.Errorf("recorded %d calls for a tool that never ran, want none", got)
	}
}
