// screenreader-mcp domain -- the StateWriter port (part of the `state` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port. ARRIVES at a reader mode, idempotently.
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: the set_state tool controller.
// HANDED OUT BY: the handshake, only when the reader announced `state`.
//
// SEPARATE INTERFACE, SAME CAPABILITY, and both halves of that are deliberate.
//
// Separate interface because a port called *inspector* that mutates is a
// mislabelled role, and because reading a mode and writing one are separately
// implementable.
//
// Same capability because the repo already answered this question for the
// analogous pair: get_config and set_config both gate on `config`. Splitting
// state while config stays joined would make an agent learn which pairs split.
// And the asymmetry that is REAL here is per-field, not per-reader -- the reader
// reports four modes and accepts one, `browseMode: "none"` is readable and not
// settable -- which a capability string cannot express and the set-domain
// rejection already does (spec 0033, "The capability question", settled
// 2026-08-20 against the spec's own first recommendation).
package ports

// StateWriter arrives at a reader mode the reader's own user has a command for.
type StateWriter interface {
	// SetState puts the reader in the requested modes and answers with the
	// state AFTER, plus the names of the fields this call actually moved.
	//
	// browseMode is "browse" or "focus". "none" is refused by the bridge,
	// which is where the reader's set-domain is known.
	SetState(request StateWrite) (StateWriteResult, error)
}

// StateWrite is the modes to arrive at. A nil field is not touched.
type StateWrite struct {
	BrowseMode *string
}

// StateWriteResult is the state after the write, and what moved.
type StateWriteResult struct {
	State ReaderState

	// Changed names the fields this call moved. EMPTY means the reader was
	// already in the asked-for state, which is a different answer from "the
	// write failed" -- that one is an error -- and from "nothing was asked".
	Changed []string
}
