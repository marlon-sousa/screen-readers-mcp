# nvdaMcpBridge domain -- TypeTextHandler: insert literal text at the focus.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `typeText`. Logs a length-only transcript entry
# then injects the text through the TextTyper port, blocking until NVDA's main
# thread has finished. A TypingError propagates to the Session, which turns it
# into an error Response -- the session survives, exactly as a rejected gesture
# does.
#
# MUTATES_READER = True: typing moves the user's machine as surely as a
# keypress does, so an observe-only session (spec 0017) refuses this handler.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class TypeTextHandler(CommandHandler):
	mutates_reader = True

	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		params = protocol.from_dict(protocol.TypeParams, request.params)
		# Logged BEFORE injection, mirroring PressGestureHandler: the length is
		# recorded even if the typer subsequently raises, so a transcript reader
		# knows an attempt was made -- never the text itself (spec 0019).
		ctx.transcript.typed(len(params.text))
		ctx.adapter_set.text_typer.type_text(params.text)
		return protocol.AckResult()
