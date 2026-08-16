# nvdaMcpBridge domain -- GetLastSpeechHandler: the most recent speech sequence.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `getLastSpeech`.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler
from .wallclock import format_wallclock

if TYPE_CHECKING:
	from .session_context import SessionContext


class GetLastSpeechHandler(CommandHandler):
	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		text, index = ctx.speech_buffer.get_last()
		return protocol.LastSpeechResult(
			text=text,
			index=index,
			# The coordinate that places this utterance on the log's timeline
			# (spec 0021); 0 for the sentinel, which no utterance ever occupies.
			logPosition=ctx.speech_buffer.log_position_at(index),
			# Empty for the sentinel, which was never emitted (spec 0028).
			emittedAt=format_wallclock(ctx.speech_buffer.time_at(index)),
		)
