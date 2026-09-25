// screenreader-mcp domain -- the FocusInspector port (the `focus` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port, the `focus` capability group.
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: the get_focus_info tool controller.
// HANDED OUT BY: the handshake, only when the reader announced `focus`.
package ports

// FocusInfo Role and States are the reader's own strings, opaque here.
type FocusInfo struct {
	Name   string
	Role   string
	States []string

	// Value and AppModule nil means the object has none, distinct from empty.
	Value     *string
	AppModule *string
}

type FocusInspector interface {
	FocusInfo() (FocusInfo, error)
}
