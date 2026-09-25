// screenreader-mcp domain -- the TextTyper port (the `typing` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port, the `typing` capability group.
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: the type_text tool controller.
// HANDED OUT BY: the handshake, only when the reader announced `typing`.
package ports

type TextTyper interface {
	// TypeText treats text as opaque; control characters go through
	// PressGestures. graceMs and announce behave as on PressGestures.
	TypeText(text string, graceMs int, announce string) (TypeOutcome, error)
}
