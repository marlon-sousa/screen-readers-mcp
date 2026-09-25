// screenreader-mcp domain -- the StateInspector port (the `state` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port, the `state` capability group.
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: the get_state tool controller.
// HANDED OUT BY: the handshake, only when the reader announced `state`.
package ports

// ReaderState values are the reader's own strings, opaque here.
type ReaderState struct {
	// BrowseMode is "browse", "focus" or "none", never empty.
	BrowseMode string

	SpeechMode string
	SleepMode  bool
	InputHelp  bool
}

type StateInspector interface {
	State() (ReaderState, error)
}
