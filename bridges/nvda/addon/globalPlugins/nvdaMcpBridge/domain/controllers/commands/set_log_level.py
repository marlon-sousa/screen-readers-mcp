# nvdaMcpBridge domain -- SetLogLevelHandler: the setLogLevel command.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for ``setLogLevel`` -- changes NVDA's own logging floor
# for the rest of the session. Forwards only: a level that was never emitted
# cannot be recovered retroactively (Python's logging decides at the *logger*).
# USES: the LogCapture port (to change the level on log.root), the announcer
# (to confirm the change audibly).
#
# ``warning`` and ``error`` are REFUSED. They joined the LogLevel enum in 0020 to
# serve as ``minLevel`` filters, where they are the common case; setting NVDA's
# own floor to either would silence warnings in the human's nvda.log for the rest
# of the session, which is a real degradation of their reader that nothing in the
# spec asks for. Same four settable levels as the server's ParseReaderLogLevel.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from ...entities.log_journal import SETTABLE_LEVELS
from .command_handler import CommandError, CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class SetLogLevelHandler(CommandHandler):
	"""Change NVDA's logging floor for the rest of the session."""

	mutates_reader = True

	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		params = protocol.from_dict(protocol.SetLogLevelParams, request.params)
		if params.level.value not in SETTABLE_LEVELS:
			valid = ", ".join(sorted(SETTABLE_LEVELS))
			raise CommandError(
				f"log level {params.level.value!r} cannot be set on the reader: "
				f"want one of {valid}. {params.level.value!r} is a getLog minLevel "
				f"filter only -- setting it would silence the user's own nvda.log."
			)
		previous = ctx.log_capture.current_level
		ctx.log_capture.set_level(params.level)
		# Say it aloud: the tester is the one whose machine just slowed down.
		ctx.announce_to_human(f"Log level {params.level.value}")
		return protocol.LogLevelResult(level=params.level, previous=previous)
