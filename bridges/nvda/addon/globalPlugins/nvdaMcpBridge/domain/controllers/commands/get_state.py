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

if TYPE_CHECKING:
	from .session_context import SessionContext


class GetStateHandler(CommandHandler):
	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		state = ctx.adapter_set.state_inspector.state()
		return protocol.StateResult(
			# The port speaks the same three strings the wire does, so this is a
			# widening into the closed set -- and it RAISES on anything else,
			# which is the point: a bridge that invented a fourth mode should
			# fail here rather than put an unknown string on the wire.
			browseMode=protocol.BrowseMode(state.browse_mode),
			speechMode=state.speech_mode,
			sleepMode=state.sleep_mode,
			inputHelp=state.input_help,
		)
