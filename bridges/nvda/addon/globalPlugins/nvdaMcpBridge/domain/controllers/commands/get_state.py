# nvdaMcpBridge domain -- GetStateHandler: answer "what mode is the reader in".
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `getState`.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler
from .observation import state_snapshot

if TYPE_CHECKING:
	from .session_context import SessionContext


class GetStateHandler(CommandHandler):
	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		return state_snapshot(ctx)
