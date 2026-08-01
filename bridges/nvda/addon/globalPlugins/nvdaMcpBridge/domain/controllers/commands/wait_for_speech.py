# nvdaMcpBridge domain -- WaitForSpeechHandler: block until text is spoken.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `waitForSpeech`. Blocks the session thread for at
# most the request's own timeout -- well below the watchdog windows, and the
# command already reset inactivity, so the wait cannot trip a deadline.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class WaitForSpeechHandler(CommandHandler):
	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		params = protocol.from_dict(protocol.WaitForSpeechParams, request.params)
		found, index, text = ctx.speech_buffer.wait_for(params.text, params.afterIndex, params.timeout)
		# On a hit, the position captured with the matching utterance; on a miss,
		# the journal's current position -- still a usable "from here" mark, and
		# the same convention `index` already follows (spec 0021).
		log_position = ctx.speech_buffer.log_position_at(index) if found else ctx.log_capture.position()
		return protocol.WaitForSpeechResult(found=found, index=index, text=text, logPosition=log_position)
