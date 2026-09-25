# nvdaMcpBridge domain -- GetSpeechHandler: speech captured since an index.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `getSpeech`.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler
from .observation import speech_entries

if TYPE_CHECKING:
	from .session_context import SessionContext


class GetSpeechHandler(CommandHandler):
	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		params = protocol.from_dict(protocol.GetSpeechParams, request.params)
		entries, from_index, to_index = ctx.speech_buffer.entries_since(params.sinceIndex)
		return protocol.SpeechResult(
			entries=speech_entries(entries),
			fromIndex=from_index,
			toIndex=to_index,
		)
