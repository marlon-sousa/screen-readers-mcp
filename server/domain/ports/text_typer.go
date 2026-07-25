// screenreader-mcp domain -- the TextTyper port (the `typing` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port. The `typing` capability group (protocol.md §4).
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: the type_text tool controller.
// HANDED OUT BY: the handshake, only when the reader announced `typing`.
package ports

// TextTyper inserts literal text into whatever holds system focus.
type TextTyper interface {
	// TypeText inserts text at the focused control, blocking until the reader
	// has processed it.
	//
	// text is OPAQUE (spec 0005 principle 3): it is not a command and this
	// server does not interpret it, exactly as a gesture id passes through
	// untouched. Newlines, Enter and any other control character are the
	// caller's job via PressGestures, not this method's.
	TypeText(text string) error
}
