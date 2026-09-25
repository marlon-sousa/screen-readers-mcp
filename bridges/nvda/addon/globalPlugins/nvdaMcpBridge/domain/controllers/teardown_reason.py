# nvdaMcpBridge domain -- TeardownReason: why a session ended.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain-only enum; it never crosses the wire.
# USED BY: the Session, SessionContext.close() and the Transcript.

from __future__ import annotations

import enum


class TeardownReason(enum.Enum):
	"""Why a session ended; the value is the transcript's SESSION CLOSE string."""

	CLIENT_BYE = "client-bye"
	CHANNEL_CLOSED = "channel-closed"
	HEARTBEAT_TIMEOUT = "heartbeat-timeout"
	INACTIVITY_TIMEOUT = "inactivity-timeout"
	HANDSHAKE_FAILED = "handshake-failed"
	EXTERNAL = "external"
