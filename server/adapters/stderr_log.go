// screenreader-mcp adapters -- StderrLog: the Log leaf.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: leaf adapter implementing the Log port by writing to stderr.
// BUILT BY: wiring/wiring.go.
// USED BY: everything that logs, through the port.
//
// Never stdout: it carries MCP frames, and one stray line corrupts the protocol.
package adapters

import (
	"fmt"
	"io"
	"os"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type StderrLog struct {
	out     io.Writer
	verbose bool
}

var _ ports.Log = (*StderrLog)(nil)

// NewStderrLog suppresses debug lines unless verbose.
func NewStderrLog(verbose bool) *StderrLog {
	return &StderrLog{out: os.Stderr, verbose: verbose}
}

func (l *StderrLog) Debugf(format string, args ...any) {
	if !l.verbose {
		return
	}
	l.write("debug", format, args...)
}

func (l *StderrLog) Infof(format string, args ...any) { l.write("info", format, args...) }

func (l *StderrLog) Errorf(format string, args ...any) { l.write("error", format, args...) }

func (l *StderrLog) write(level, format string, args ...any) {
	fmt.Fprintf(l.out, "screenreader-mcp %s: %s\n", level, fmt.Sprintf(format, args...))
}
