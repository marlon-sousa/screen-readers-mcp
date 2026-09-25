# nvdaMcpBridge domain -- WaitForLogHandler: block until a matching record lands.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `waitForLog`, blocking until a record matches, the clamped timeout elapses,
# or teardown is requested.
# The teardown poll is required: the panic gesture joins this thread from NVDA's main thread.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from ...entities.indexed_buffer import POLL_INTERVAL
from .command_handler import MAX_POLL_TIMEOUT, CommandHandler

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
		timeout = min(max(0.0, params.timeout), MAX_POLL_TIMEOUT)
		if timeout < params.timeout:
			ctx.transcript.note(
				f"waitForLog: timeout {params.timeout} clamped to {MAX_POLL_TIMEOUT} "
				f"(the inactivity window is not extended by a blocking handler); "
				f"wait again to keep watching"
			)
		deadline = ctx.clock.monotonic() + timeout
		while True:
			match = ctx.log_capture.find_since(start, min_level=params.minLevel, contains=params.contains)
			if match is not None:
				return match
			if ctx.clock.monotonic() >= deadline:
				return None
			if ctx.teardown_requested():
				# A miss, not an error, so the caller gets an ordinary `found: false`.
				return None
			ctx.clock.sleep(POLL_INTERVAL)
