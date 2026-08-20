# nvdaMcpBridge domain -- AnnounceHandler: speak a hint to the human.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `announce`. Voices a short hint to the tester through
# the Announcer, which drives the reader's real (still-loaded) synth directly --
# audible even in silent mode, where NVDA's speak() output is suppressed but the
# synth itself is untouched. Returns the generic ack.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class AnnounceHandler(CommandHandler):
	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		params = protocol.from_dict(protocol.AnnounceParams, request.params)
		ctx.announcer.announce(params.text)
		# AFTER the sound, never before: the silence cap measures how long the human
		# has been unable to hear their machine, so its clock resets when they were
		# actually told rather than when we decided to tell them (spec 0032).
		ctx.note_audible()
		return protocol.AckResult()
