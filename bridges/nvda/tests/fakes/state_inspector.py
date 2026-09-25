# nvdaMcpBridge tests -- FakeStateInspector, standing in for the StateInspector port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# Defaults to browse so it agrees with FakeStateSetter, which the fake factory wires to it.

from __future__ import annotations

from nvdaMcpBridge.domain.ports.state_inspector import ReaderState, StateInspector


class FakeStateInspector(StateInspector):
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
