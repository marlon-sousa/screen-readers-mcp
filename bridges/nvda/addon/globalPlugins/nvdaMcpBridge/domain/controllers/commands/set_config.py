# nvdaMcpBridge domain -- SetConfigHandler: write the reader's config (temporarily).
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `setConfig`. Parses the keyPath and value, writes
#       through the ConfigAccessor port, and returns the prior value. The change
#       is visible to the running reader immediately, but never persists to disk
#       -- the ConfigAccessor records the prior value on first write to each key,
#       and session teardown restores every key this session touched.
#
# MUTATES_READER = True: writing config changes the reader's behaviour in memory
# as surely as a keypress does, so an observe-only session (spec 0017) refuses
# this handler.

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
