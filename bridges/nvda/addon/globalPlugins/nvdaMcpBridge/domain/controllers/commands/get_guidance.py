# nvdaMcpBridge domain -- GetGuidanceHandler: what this reader says about the stance.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `getGuidance`, answering for the session's own persona fixed at hello.
# marks_log is False: it reads a shipped file, and an empty log window would push a real one out of the
# journal's last fifty.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from ...entities.reader_guidance import guidance_for
from .command_handler import CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class GetGuidanceHandler(CommandHandler):
	marks_log = False

	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		text, recognised = guidance_for(ctx.persona, ctx.gesture_resolver)
		return protocol.GetGuidanceResult(
			# Echoed as received, including an unrecognised value.
			persona=ctx.persona,
			recognised=recognised,
			text=text,
		)
