// screenreader-mcp domain -- ReaderLogLevel: the reader's own log verbosity.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity, the optional per-session level of the reader's own diagnostic log, not this server's logging.
// BUILT BY: the agent, through connect_reader's `log_level` parameter.
// READ BY: adapters/bridge/handshake.go, which sends it in `hello`.
package entities

import (
	"fmt"
	"strings"
)

type ReaderLogLevel string

const (
	ReaderLogDebug        ReaderLogLevel = "debug"
	ReaderLogIO           ReaderLogLevel = "io"
	ReaderLogDebugWarning ReaderLogLevel = "debugwarning"
	ReaderLogInfo         ReaderLogLevel = "info"
)

func (l ReaderLogLevel) String() string { return string(l) }

func ParseReaderLogLevel(value string) (ReaderLogLevel, error) {
	switch ReaderLogLevel(value) {
	case ReaderLogDebug, ReaderLogIO, ReaderLogDebugWarning, ReaderLogInfo:
		return ReaderLogLevel(value), nil
	default:
		valid := []string{
			string(ReaderLogDebug), string(ReaderLogIO),
			string(ReaderLogDebugWarning), string(ReaderLogInfo),
		}
		return "", fmt.Errorf("log level %q: want one of %s", value, strings.Join(valid, ", "))
	}
}
