// screenreader-mcp domain -- the Interact port (the `interact` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port. The `interact` capability group (protocol.md §4), covering
// announce, askUser, and waitForUserReply -- every command that addresses a HUMAN
// rather than the reader's state.
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: the announce, ask_user and wait_for_user_reply tool controllers.
// HANDED OUT BY: the handshake, only when the reader announced `interact`.
//
// This is the only port group that reaches a HUMAN rather than the reader's
// state. Everything else here observes or drives a screen reader; this speaks to
// the person sitting in front of it, through the reader's real synthesizer and
// underneath whatever suppression the capture mode has in place. A reader whose
// bridge has no way to do that simply never announces the capability, and the
// tools are never advertised -- the same structural gate as braille, for the
// same reason.
package ports

import "time"

// Interact is everything the `interact` capability can be asked.
type Interact interface {
	// Announce speaks text to the human operating the reader.
	Announce(text string) error

	// AskUser presents a prompt and returns a ticket immediately.
	AskUser(prompt string) (string, error)

	// WaitForUserReply polls for the answer to an outstanding prompt.
	WaitForUserReply(ticket string, timeout time.Duration) (UserReply, error)
}

// UserReply is the human's answer to an askUser prompt.
//
// Text is always empty in stage 1 (the acknowledgement gesture carries no
// text); it ships so stage 2 (a dialog) populates it without a wire break.
type UserReply struct {
	Answered bool
	Text     string
}
