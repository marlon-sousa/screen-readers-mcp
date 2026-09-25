# nvdaMcpBridge domain -- ByeHandler: the client ends the session.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `bye`.
# The Session writes the ack before it honours the teardown, so the client always sees it.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from ..teardown_reason import TeardownReason
from .command_handler import CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class ByeHandler(CommandHandler):
	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		ctx.close(TeardownReason.CLIENT_BYE)
		return protocol.AckResult()
