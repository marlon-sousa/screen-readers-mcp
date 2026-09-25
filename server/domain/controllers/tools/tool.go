// screenreader-mcp domain -- the Tool interface and CapabilityError.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: the interface every tool controller implements, plus its signalling type.
// IMPLEMENTED BY: one file per tool in this directory.
// LISTED BY: registry.go. RUN BY: dispatcher.go. BOUND BY: adapters/mcp.
package tools

import (
	"encoding/json"
	"fmt"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// Implementations are stateless singletons; all per-call state arrives in the ToolContext.
type Tool interface {
	Name() string

	// Capability is empty for an ungated tool.
	Capability() entities.Capability

	Description() string

	InputSchema() json.RawMessage

	// OutputSchema describes a successful result; the SDK does not check results against it, so output_schema_test.go does.
	OutputSchema() json.RawMessage

	// params may be nil: a client calling a no-parameter tool sends no arguments at all.
	Execute(ctx ToolContext, params json.RawMessage) (any, error)
}

// CapabilityError is a call for a capability the live reader lacks, or for a gated tool while no reader is connected.
type CapabilityError struct {
	Tool string

	// Capability is empty when the tool is ungated and the problem is that nothing is connected.
	Capability entities.Capability

	// Reader is empty when no reader is connected.
	Reader string

	// Step is the plan step that needed it, counting from 1, or 0 for an ordinary call.
	Step int
}

func (e *CapabilityError) Error() string {
	if e.Reader == "" {
		return fmt.Sprintf(
			"%s needs a connected reader, and none is: call connect_reader first",
			e.Tool)
	}
	if e.Step > 0 {
		return fmt.Sprintf(
			"%s step %d needs the %q capability, which the connected reader %q "+
				"did not announce; the plan was refused whole and nothing was delivered",
			e.Tool, e.Step, e.Capability, e.Reader)
	}
	return fmt.Sprintf(
		"%s needs the %q capability, which the connected reader %q did not announce",
		e.Tool, e.Capability, e.Reader)
}
