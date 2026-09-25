# nvdaMcpBridge domain -- TypeTextHandler: insert literal text at the focus.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `typeText`, reporting the speech that arrived in the grace window.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler
from .observation import speech_entries, state_snapshot

if TYPE_CHECKING:
	from .session_context import SessionContext


class TypeTextHandler(CommandHandler):
	mutates_reader = True

	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		params = protocol.from_dict(protocol.TypeParams, request.params)
		grace = max(0, params.graceMs) / 1000.0
		buffer = ctx.speech_buffer

		if params.announce.strip():
			ctx.announce_to_human(params.announce)

		start_index = buffer.next_index()
		# Logged before injection so a failed attempt is still recorded; only the length, never the text.
		ctx.transcript.typed(len(params.text))
		ctx.adapter_set.text_typer.type_text(params.text)
		buffer.collect_since(start_index, grace)

		entries, from_index, to_index = buffer.entries_since(start_index)
		return protocol.TypeResult(
			# Never the text: typing is how a secret is entered.
			typed=len(params.text),
			speech=speech_entries(entries),
			speechFrom=from_index,
			speechTo=to_index,
			state=state_snapshot(ctx),
		)
