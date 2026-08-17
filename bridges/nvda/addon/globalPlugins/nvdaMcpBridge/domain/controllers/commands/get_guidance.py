# nvdaMcpBridge domain -- GetGuidanceHandler: what this reader says about the stance.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `getGuidance` (spec 0029 Part 4). Answers for the
#       session's OWN persona, fixed at hello, and takes no parameters.
#
# NO `persona` PARAMETER, deliberately. One would let an agent fetch the
# validator's instructions from a session standing in for a user, which quietly
# turns the persona into something you consult rather than something you are --
# and it would raise a question about which of the two wins that nobody should
# have to answer.
#
# marks_log = False: this reads a file the addon shipped and touches nothing NVDA
# logs, so opening a log window for it would put an empty span in the journal and
# push a real one out of the last fifty.

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
		text, recognised = guidance_for(ctx.persona)
		return protocol.GetGuidanceResult(
			# Echoed AS RECEIVED, including an unrecognised value: the field says
			# what was asked, so a server can tell which declaration this document
			# answers without holding its own bookkeeping.
			persona=ctx.persona,
			recognised=recognised,
			text=text,
		)
