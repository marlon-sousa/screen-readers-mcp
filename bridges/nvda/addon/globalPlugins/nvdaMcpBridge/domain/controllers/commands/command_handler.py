# nvdaMcpBridge domain -- CommandHandler: the per-command controller interface.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: the interface every command handler implements.
# USED BY: the Session and registry.py.
# A handler fails a command by raising; the Session turns that into an error Response.

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
	from .... import protocol
	from .session_context import SessionContext


#: The longest any blocking command may hold the session thread; it must stay inside the 120 s
#: inactivity window, which a blocking handler does not refresh.
MAX_POLL_TIMEOUT: float = 110.0


class CommandError(Exception):
	"""A handler-level failure that becomes an error Response."""


class CommandHandler(ABC):
	#: ``ping`` sets this False: it proves liveness, not that the agent is still testing.
	resets_inactivity: bool = True

	available_before_hello: bool = False

	#: True for a command that moves the user's machine, which an observe-only session refuses; the default
	#: is False, so a new mutating command must opt in.
	mutates_reader: bool = False

	#: GetLogHandler sets this False, so a getLog call is not its own anchor.
	marks_log: bool = True

	@abstractmethod
	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		"""Run the command and return its wire result, or raise to fail it."""
