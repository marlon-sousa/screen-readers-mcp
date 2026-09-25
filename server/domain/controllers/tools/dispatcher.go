// screenreader-mcp domain -- Dispatcher: one tool call, as a use case.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: controller; builds the per-call ToolContext, runs the named tool, and applies the rule every call shares.
// DEPENDS ON: the Registry, ConnectionControl, and the Clock and Log ports.
// BUILT BY: wiring/wiring.go. USED BY: adapters/mcp, as the one route from an MCP request to a tool.
package tools

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// Dispatcher is stateless between calls: the context is built fresh from the controller's current connection each time.
type Dispatcher struct {
	registry *Registry
	control  ConnectionControl
	clock    ports.Clock
	log      ports.Log
	record   *entities.SessionRecord
}

func NewDispatcher(
	registry *Registry,
	control ConnectionControl,
	clock ports.Clock,
	log ports.Log,
	record *entities.SessionRecord,
) *Dispatcher {
	if record == nil {
		record = entities.NewSessionRecord()
	}
	return &Dispatcher{registry: registry, control: control, clock: clock, log: log, record: record}
}

func (d *Dispatcher) Record() *entities.SessionRecord { return d.record }

// ErrUnknownTool should be unreachable through the MCP adapter; if it is returned, the wiring is wrong.
var ErrUnknownTool = errors.New("no such tool")

// Execute tells the connection controller when a call died of a lost connection; an ordinary bridge refusal leaves the session up.
func (d *Dispatcher) Execute(name string, params json.RawMessage) (any, error) {
	tool, known := d.registry.Lookup(name)
	if !known {
		return nil, fmt.Errorf("%w: %q", ErrUnknownTool, name)
	}

	result, err := tool.Execute(d.context(name), params)
	d.recordCall(name, params, result, err)
	if err != nil && errors.Is(err, ports.ErrConnectionLost) {
		d.log.Infof("tool %q found the connection gone; re-checking it", name)
		// Verify records the loss; its own error is not this call's answer.
		_, _ = d.control.Verify()
	}
	return result, err
}

// recordCall must never fail the call: it is a diagnostic.
func (d *Dispatcher) recordCall(name string, params json.RawMessage, result any, err error) {
	call := entities.RecordedCall{
		At:     d.clock.Now(),
		Tool:   name,
		Params: string(params),
	}
	if err != nil {
		call.Failed = true
		call.Error = err.Error()
	} else if encoded, marshalErr := json.Marshal(result); marshalErr == nil {
		call.Result = string(encoded)
	} else {
		call.Result = fmt.Sprintf("<unrenderable result: %v>", marshalErr)
	}
	d.record.Add(call)
}

func (d *Dispatcher) context(name string) ToolContext {
	return ToolContext{
		Tool:       name,
		Control:    d.control,
		Connection: d.control.Current(),
		Clock:      d.clock,
		Log:        d.log,
	}
}
