# nvdaMcpBridge domain -- SetLogLevelHandler: the setLogLevel command.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for ``setLogLevel`` -- raises or lowers NVDA's own logging
# floor for the rest of the session. Forwards only: a level that was never emitted
# cannot be recovered retroactively (Python's logging decides at the *logger*).
# USES: the LogCapture port (to change the level on log.root), the announcer
# (to confirm the change audibly).

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler

if TYPE_CHECKING:
    from .session_context import SessionContext


class SetLogLevelHandler(CommandHandler):
    """Change NVDA's logging floor for the rest of the session."""

    mutates_reader = True

    def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
        params = protocol.from_dict(protocol.SetLogLevelParams, request.params)
        previous = ctx.log_capture.current_level
        ctx.log_capture.set_level(params.level)
        # Say it aloud: the tester is the one whose machine just slowed down.
        ctx.announcer.announce(f"Log level {params.level.value}")
        return protocol.LogLevelResult(level=params.level, previous=previous)
