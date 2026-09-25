# nvdaMcpBridge domain -- GetNextSpeechIndexHandler: the next bookmark.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `getNextSpeechIndex`.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class GetNextSpeechIndexHandler(CommandHandler):
	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		return protocol.NextIndexResult(index=ctx.speech_buffer.next_index())
