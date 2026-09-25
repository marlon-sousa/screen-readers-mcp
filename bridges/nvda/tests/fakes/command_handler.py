# nvdaMcpBridge tests -- FakeCommandHandler, standing in for a CommandHandler.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from collections.abc import Callable
from typing import TYPE_CHECKING, Any

from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.command_handler import CommandHandler

if TYPE_CHECKING:
	from nvdaMcpBridge.domain.controllers.commands.session_context import SessionContext


class FakeCommandHandler(CommandHandler):
	def __init__(
		self,
		*,
		result: Any = None,
		error: Exception | None = None,
		resets_inactivity: bool = True,
		available_before_hello: bool = False,
		marks_log: bool = True,
		on_execute: Callable[[SessionContext], None] | None = None,
	) -> None:
		self._result = result if result is not None else p.AckResult()
		self._error = error
		self.resets_inactivity = resets_inactivity
		self.available_before_hello = available_before_hello
		self.marks_log = marks_log
		# Runs inside the dispatch, between this command's two log marks.
		self._on_execute = on_execute
		self.calls: list[p.Request] = []

	def execute(self, ctx: SessionContext, request: p.Request) -> Any:
		self.calls.append(request)
		if self._on_execute is not None:
			self._on_execute(ctx)
		if self._error is not None:
			raise self._error
		return self._result
