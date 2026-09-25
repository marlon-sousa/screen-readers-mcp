# nvdaMcpBridge tests -- FakeSession, a controllable stand-in for the Session.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: test scaffolding; a Session stand-in for BridgeServer's connection lifecycle tests.
from __future__ import annotations

import threading

from nvdaMcpBridge.domain.controllers.session import Session
from nvdaMcpBridge.domain.controllers.teardown_reason import TeardownReason


class FakeSession(Session):
	def __init__(self, transport: object) -> None:
		# No super().__init__: BridgeServer only calls run() and request_teardown().
		self.transport = transport
		self.teardown_reason: TeardownReason | None = None
		self.torn_down = 0
		self.started = threading.Event()
		self._done = threading.Event()

	def run(self) -> None:
		self.started.set()
		try:
			self._done.wait()
		finally:
			self.torn_down += 1

	def request_teardown(self, reason: TeardownReason) -> None:
		self.teardown_reason = reason
		self._done.set()

	def finish(self) -> None:
		"""Simulate a natural end (bye / EOF): run() returns with no teardown reason."""
		self._done.set()
