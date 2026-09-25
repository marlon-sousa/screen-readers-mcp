# nvdaMcpBridge domain -- WaitForSpeechHandler: block until text is spoken.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `waitForSpeech`.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler
from .wallclock import format_wallclock

if TYPE_CHECKING:
	from .session_context import SessionContext


class WaitForSpeechHandler(CommandHandler):
	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		params = protocol.from_dict(protocol.WaitForSpeechParams, request.params)
		found, index, text = ctx.speech_buffer.wait_for(params.text, params.afterIndex, params.timeout)
		# On a miss, the journal's current position, still usable as a "from here" mark.
		log_position = ctx.speech_buffer.log_position_at(index) if found else ctx.log_capture.position()
		# Empty on a miss: there is no instant for speech that never arrived.
		emitted_at = format_wallclock(ctx.speech_buffer.time_at(index)) if found else ""
		return protocol.WaitForSpeechResult(
			found=found,
			index=index,
			text=text,
			logPosition=log_position,
			emittedAt=emitted_at,
		)
