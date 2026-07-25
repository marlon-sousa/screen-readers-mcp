# nvdaMcpBridge domain -- GetFocusInfoHandler: answer "where am I".
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `getFocusInfo`. Reads the focus snapshot from the
#       FocusInspector port and maps its DTO field names to the wire's camelCase
#       names (e.g. app_module -> appModule), exactly as GetBrailleHandler maps
#       its result.
#
# A null focus yields an empty FocusInfoResult (all fields defaulted), not an
# error -- the agent checks for "no focus" with the same assertion it uses for
# "a button is focused".

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
