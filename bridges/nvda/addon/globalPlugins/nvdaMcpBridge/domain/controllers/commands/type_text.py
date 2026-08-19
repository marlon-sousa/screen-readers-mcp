# nvdaMcpBridge domain -- TypeTextHandler: insert literal text at the focus.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `typeText`. Logs a length-only transcript entry
# then injects the text through the TextTyper port, blocking until NVDA's main
# thread has finished, and reports what was said within the grace window. A
# TypingError propagates to the Session, which turns it into an error Response
# -- the session survives, exactly as a rejected gesture does.
#
# MUTATES_READER = True: typing moves the user's machine as surely as a
# keypress does, so an observe-only session (spec 0017) refuses this handler.
#
# THE GRACE DEFAULTS TO ZERO HERE, and to 100 ms on pressGesture (spec 0025,
# settled 2026-08-16). Two defaults for one mechanism looks inconsistent until
# you ask what the speech is worth: a gesture produces one announcement worth
# reading, while typing with "speak typed characters" on produces one utterance
# per character and none of them is worth waiting for. Matching the two would be
# consistency in the wrong dimension. The state snapshot, by contrast, IS
# returned here -- four small fields, never misleading, and an agent pays more
# for the asymmetry in confusion than the bytes cost in transport.

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
			ctx.announcer.announce(params.announce)

		start_index = buffer.next_index()
		# Logged BEFORE injection, mirroring PressGestureHandler: the length is
		# recorded even if the typer subsequently raises, so a transcript reader
		# knows an attempt was made -- never the text itself (spec 0019).
		ctx.transcript.typed(len(params.text))
		ctx.adapter_set.text_typer.type_text(params.text)
		buffer.collect_since(start_index, grace)

		entries, from_index, to_index = buffer.entries_since(start_index)
		return protocol.TypeResult(
			# The length, not the text: typing is exactly how a secret would be
			# entered, and echoing it back would put the secret in the result
			# (spec 0019). Counted in characters, so an accented one counts once.
			typed=len(params.text),
			speech=speech_entries(entries),
			speechFrom=from_index,
			speechTo=to_index,
			state=state_snapshot(ctx),
		)
