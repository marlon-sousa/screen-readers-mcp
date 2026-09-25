# nvdaMcpBridge domain -- WaitForSpeechToFinishHandler: block until NVDA stops.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `waitForSpeechToFinish`; the finish signal is the speech buffer's concern.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class WaitForSpeechToFinishHandler(CommandHandler):
	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		params = protocol.from_dict(protocol.WaitToFinishParams, request.params)
		return protocol.WaitToFinishResult(finished=ctx.speech_buffer.wait_to_finish(params.timeout))
