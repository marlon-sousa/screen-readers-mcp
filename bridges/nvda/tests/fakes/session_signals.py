# nvdaMcpBridge tests -- FakeSessionSignals, standing in for the SessionSignals port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# FAKES: domain/ports/session_signals.py
#
# Counts the start/end cues so a test can assert the beeps fired exactly when a
# session established and when it tore down.

from __future__ import annotations

from nvdaMcpBridge.domain.ports.session_signals import SessionSignals


class FakeSessionSignals(SessionSignals):
	"""Records how many times each session cue was signalled."""

	def __init__(self) -> None:
		self.started = 0
		self.ended = 0
		#: Every persona the start cue was given, in order -- so a test can assert
		#: not merely that the cue fired but what it announced (spec 0029).
		self.personas: list[str] = []

	def session_started(self, persona: str) -> None:
		self.started += 1
		self.personas.append(persona)

	def session_ended(self) -> None:
		self.ended += 1
