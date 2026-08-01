# nvdaMcpBridge domain -- WaitForLogHandler: block until a matching record lands.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `waitForLog` -- the journal's counterpart to
# waitForSpeech (spec 0021). Blocks the session thread until a record matches,
# the caller's timeout elapses, or the session is asked to end.
#
# Pull, not push: the agent asks and waits. Nothing here tails or pushes lines
# unasked (0020's rejection of that stands).
#
# TWO BOUNDS, and both are about the same watchdog. A single wait is CLAMPED to
# MAX_POLL_TIMEOUT -- the shared cap on any blocking command, and the reasoning
# for it lives with the constant in command_handler.py.
#
# And the loop watches for teardown, because clamping alone is not enough: the
# panic gesture calls BridgeServer.stop(), which JOINS this thread from NVDA's
# main thread. waitForUserReply solves that by having the teardown request cancel
# the prompt the handler is blocked on; a wait with no such entity behind it has
# to poll for it. Without this, pressing panic during a two-minute waitForLog
# would freeze the reader until the wait expired.

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
				# A miss, not an error: the session is ending, and the caller gets
				# the ordinary `found: false` rather than a fault to interpret.
				return None
			ctx.clock.sleep(POLL_INTERVAL)
