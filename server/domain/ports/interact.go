// screenreader-mcp domain -- the Interact port (the `interact` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port, the `interact` capability group: every command that addresses the human rather than the reader.
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: the announce, ask_user and wait_for_user_reply tool controllers.
// HANDED OUT BY: the handshake, only when the reader announced `interact`.
package ports

import "time"

type Interact interface {
	Announce(text string) error

	AskUser(prompt string) (string, error)

	WaitForUserReply(ticket string, timeout time.Duration) (UserReply, error)
}

// UserReply.Text is empty while the acknowledgement is a gesture, which carries no text.
type UserReply struct {
	Answered bool
	Text     string
}
