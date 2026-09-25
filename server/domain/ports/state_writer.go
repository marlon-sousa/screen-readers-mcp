// screenreader-mcp domain -- the StateWriter port (part of the `state` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port, arrives at a reader mode idempotently.
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: the set_state tool controller.
// HANDED OUT BY: the handshake, only when the reader announced `state`.
package ports

type StateWriter interface {
	// SetState answers with the state after the write; the bridge refuses
	// browseMode "none".
	SetState(request StateWrite) (StateWriteResult, error)
}

// StateWrite nil fields are not touched.
type StateWrite struct {
	BrowseMode *string
}

type StateWriteResult struct {
	State ReaderState

	// Changed empty means the reader was already in the asked-for state.
	Changed []string
}
