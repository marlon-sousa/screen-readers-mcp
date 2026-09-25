# nvdaMcpBridge domain -- SetConfigHandler: write the reader's config (temporarily).
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `setConfig`, writing through the ConfigAccessor and returning the prior value.
# The change is never persisted: teardown restores every key the session touched.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class SetConfigHandler(CommandHandler):
	mutates_reader = True

	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		params = protocol.from_dict(protocol.SetConfigParams, request.params)
		prior = ctx.adapter_set.config_accessor.set(params.keyPath, params.value)
		return protocol.ConfigResult(value=prior)
