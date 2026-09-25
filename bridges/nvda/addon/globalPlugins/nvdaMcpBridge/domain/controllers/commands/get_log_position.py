# nvdaMcpBridge domain -- GetLogPositionHandler: mark the present, return nothing.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `getLogPosition`: the journal position and wall clock, with no records.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler
from .wallclock import format_wallclock

if TYPE_CHECKING:
	from .session_context import SessionContext


class GetLogPositionHandler(CommandHandler):
	# It is the mark itself, so it opens no log window.
	marks_log = False

	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		return protocol.LogPositionResult(
			position=ctx.log_capture.position(),
			time=format_wallclock(ctx.clock.time()),
		)
