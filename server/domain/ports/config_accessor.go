// screenreader-mcp domain -- the ConfigAccessor port (the `config` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port, the `config` capability group.
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: the get_config and set_config tool controllers.
// HANDED OUT BY: the handshake, only when the reader announced `config`.
package ports

import "encoding/json"

// ConfigAccessor treats key paths and values as opaque; values round-trip byte for byte.
type ConfigAccessor interface {
	GetConfig(keyPath []string) (json.RawMessage, error)

	// SetConfig returns what the reader now holds, which a reader may have normalised.
	SetConfig(keyPath []string, value json.RawMessage) (json.RawMessage, error)
}
