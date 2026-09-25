# nvdaMcpBridge tests -- FakeSessionSignals, standing in for the SessionSignals port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from nvdaMcpBridge.domain.ports.session_signals import SessionSignals


class FakeSessionSignals(SessionSignals):
	def __init__(self) -> None:
		self.started = 0
		self.ended = 0
		self.personas: list[str] = []

	def session_started(self, persona: str) -> None:
		self.started += 1
		self.personas.append(persona)

	def session_ended(self) -> None:
		self.ended += 1
