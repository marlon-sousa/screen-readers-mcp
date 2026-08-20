# nvdaMcpBridge domain -- PingHandler: liveness probe.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `ping`. Proves the peer is alive (which resets the
# heartbeat, in the Session) but NOT that the agent is still testing -- so it
# deliberately does not reset the command-inactivity watchdog. And it certainly
# does not reset the SILENCE cap: a keepalive tells the human nothing.
#
# It also reports whether speech is being withheld from the human RIGHT NOW, which
# is how a silence-cap lift is discoverable by asking (spec 0032 Part 5). This is
# the command `status` makes its round trip with, and status is the one ungated
# tool that answers with proof rather than memory -- so the fact rides on the
# probe that was already being sent rather than costing a trip of its own.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class PingHandler(CommandHandler):
	resets_inactivity = False

	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		suppressing = None
		if ctx.adapters is not None:
			suppressing = ctx.adapters.speech_source.is_suppressing()
		return protocol.PingResult(suppressing=suppressing)
