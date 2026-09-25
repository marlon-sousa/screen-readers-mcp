# nvdaMcpBridge domain -- PingHandler: liveness probe.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `ping`, which reports whether speech is being withheld from the human.
# A ping must not reset the inactivity watchdog or the silence cap: a keepalive says nothing about testing.

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
