# nvdaMcpBridge domain -- GetConfigHandler: read the reader's config.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `getConfig`.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class GetConfigHandler(CommandHandler):
	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		params = protocol.from_dict(protocol.GetConfigParams, request.params)
		value = ctx.adapter_set.config_accessor.get(params.keyPath)
		return protocol.ConfigResult(value=value)
