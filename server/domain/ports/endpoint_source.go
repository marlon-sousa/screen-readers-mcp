// screenreader-mcp domain -- the EndpointSource port.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port, the configured reader set.
// IMPLEMENTED BY: config/loader.go.
// USED BY: the connection controller.
//
// Every reader it returns is known before the process starts; nothing is invented at runtime.
package ports

import "github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"

type EndpointSource interface {
	// Readers keeps each reader's endpoints in declared order.
	Readers() []entities.ConfiguredReader
}
