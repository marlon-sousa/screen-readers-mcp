# nvdaMcpBridge domain -- GetBrailleHandler: braille captured since an index.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `getBraille`. The braille counterpart of getSpeech:
# each update crosses the wire as its own entry, carrying the journal position
# it was captured at (spec 0021).

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class GetBrailleHandler(CommandHandler):
	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		params = protocol.from_dict(protocol.GetBrailleParams, request.params)
		entries, from_index, to_index = ctx.braille_buffer.entries_since(params.sinceIndex)
		return protocol.BrailleResult(
			entries=[
				protocol.BrailleEntry(text=text, index=index, logPosition=log_position)
				for text, index, log_position in entries
			],
			fromIndex=from_index,
			toIndex=to_index,
		)
