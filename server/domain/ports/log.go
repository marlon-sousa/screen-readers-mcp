// screenreader-mcp domain -- the Log port.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port, diagnostics for the domain and the adapters.
// IMPLEMENTED BY: adapters/stderr_log.go, and fakes/log.go in tests.
// USED BY: the bridge client and the connection controller.
//
// Stdout carries MCP frames only; one stray print corrupts the JSON-RPC stream.
package ports

type Log interface {
	Debugf(format string, args ...any)

	Infof(format string, args ...any)

	Errorf(format string, args ...any)
}
