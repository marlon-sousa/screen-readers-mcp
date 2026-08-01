# nvdaMcpBridge domain -- WaitForLogHandler: block until a matching record lands.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `waitForLog` -- the journal's counterpart to
# waitForSpeech (spec 0021). Blocks the session thread for at most the request's
# own timeout, well below the watchdog windows; the Session's post-dispatch
# heartbeat refresh (spec 0016) is what lets a long wait survive.
#
# Pull, not push: the agent asks and waits. Nothing here tails or pushes lines
# unasked (0020's rejection of that stands).

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from ...entities.indexed_buffer import POLL_INTERVAL
from .command_handler import CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class WaitForLogHandler(CommandHandler):
	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		params = protocol.from_dict(protocol.WaitForLogParams, request.params)
		start = ctx.log_capture.position()
		match = self._wait(ctx, start, params)
		if match is not None:
			position, text = match
			return protocol.WaitForLogResult(found=True, position=position, text=text)
		return protocol.WaitForLogResult(found=False, position=ctx.log_capture.position(), text="")

	@staticmethod
	def _wait(ctx: SessionContext, start: int, params: protocol.WaitForLogParams) -> tuple[int, str] | None:
		deadline = ctx.clock.monotonic() + max(0.0, params.timeout)
		while True:
			match = ctx.log_capture.find_since(start, min_level=params.minLevel, contains=params.contains)
			if match is not None:
				return match
			if ctx.clock.monotonic() >= deadline:
				return None
			ctx.clock.sleep(POLL_INTERVAL)
