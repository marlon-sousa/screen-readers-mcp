# nvdaMcpBridge domain -- GetFocusInfoHandler: answer "where am I".
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `getFocusInfo`.
# A null focus yields an empty FocusInfoResult, not an error.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class GetFocusInfoHandler(CommandHandler):
	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		info = ctx.adapter_set.focus_inspector.focus_info()
		return protocol.FocusInfoResult(
			name=info.name,
			role=info.role,
			states=info.states,
			value=info.value,
			appModule=info.app_module,
		)
