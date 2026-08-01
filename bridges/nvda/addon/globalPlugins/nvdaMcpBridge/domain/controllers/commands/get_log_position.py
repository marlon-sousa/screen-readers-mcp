# nvdaMcpBridge domain -- GetLogPositionHandler: mark the present, return nothing.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `getLogPosition` -- the programmatic F1 ritual (spec
# 0021). Returns the journal's current append position and wall clock, and NO
# records: paying for a slice to learn a single integer defeats the purpose of
# marking the moment you start observing.
#
# A separate command rather than reading the cursor off a getLog response, for
# the same reason getNextSpeechIndex is separate from getSpeech.

from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class GetLogPositionHandler(CommandHandler):
	# Marks nothing itself -- it IS the mark. Giving it a window would anchor
	# getLog on a command that, by construction, logged nothing.
	marks_log = False

	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		return protocol.LogPositionResult(
			position=ctx.log_capture.position(),
			time=self._wallclock(ctx),
		)

	@staticmethod
	def _wallclock(ctx: SessionContext) -> str:
		# Same shape as FileTranscript's own timestamps (with the date, unlike
		# NVDA's own time-only log format), so a mark lines up against the
		# transcript, the journal's `created` field, and the human's "around
		# then" without a format negotiation.
		return datetime.fromtimestamp(ctx.clock.time()).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
