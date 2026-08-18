# nvdaMcpBridge domain -- GetStateHandler: answer "what mode is the reader in".
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `getState`. Reads the reader's mode-state from the
#       StateInspector port and maps its DTO field names to the wire's camelCase
#       names (e.g. browse_mode -> browseMode).

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler
from .observation import state_snapshot

if TYPE_CHECKING:
	from .session_context import SessionContext


class GetStateHandler(CommandHandler):
	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		# The same snapshot pressGesture and typeText now put on their results
		# (spec 0025), so the mapping lives in one place rather than three.
		return state_snapshot(ctx)
