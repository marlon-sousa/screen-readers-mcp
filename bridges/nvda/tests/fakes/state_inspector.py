# nvdaMcpBridge tests -- FakeStateInspector, standing in for the StateInspector port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# FAKES: domain/ports/state_inspector.py
#
# Returns a configurable ReaderState snapshot. Defaults to a plausible state
# (talking, not sleeping, no input help, in a browsable document) so a bare
# roundtrip test doesn't need to seed one. Browse rather than "none" so it agrees
# with FakeStateSetter's own default: the pair is wired together in the fake
# factory, and two fakes disagreeing about the same reader would be a trap.

from __future__ import annotations

from nvdaMcpBridge.domain.ports.state_inspector import ReaderState, StateInspector


class FakeStateInspector(StateInspector):
	"""Returns a configurable ReaderState; records every call."""

	def __init__(self) -> None:
		self.calls: list[None] = []
		self.reader_state: ReaderState = ReaderState(
			browse_mode="browse",
			speech_mode="talk",
			sleep_mode=False,
			input_help=False,
		)

	def state(self) -> ReaderState:
		self.calls.append(None)
		return self.reader_state
