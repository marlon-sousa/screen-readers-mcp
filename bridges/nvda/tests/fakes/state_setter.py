# nvdaMcpBridge tests -- FakeStateSetter, standing in for the StateSetter port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# FAKES: domain/ports/state_setter.py
#
# It holds a browse mode and COMPARES INSIDE ITSELF, exactly as the real adapter
# compares inside NVDA -- so a test can assert that already-there wrote nothing
# without reaching into the handler, and so a handler that started comparing on
# its own would show up here as a redundant call rather than pass silently.
#
# Set `fail_with` to make it raise StateSetError, which is how the real adapter
# reports a focus that is not a browsable document.

from __future__ import annotations

import dataclasses

from nvdaMcpBridge.domain.ports.state_setter import StateSetError, StateSetter

from .state_inspector import FakeStateInspector


class FakeStateSetter(StateSetter):
	"""Remembers the mode it holds, records every target asked for."""

	def __init__(self, browse_mode: str = "browse", inspector: FakeStateInspector | None = None) -> None:
		self.browse_mode = browse_mode
		#: When the fake factory wires one in, a successful write shows up in
		#: what the INSPECTOR then reports -- which is what the real pair does
		#: through NVDA, and what lets a round-trip test assert the state on the
		#: result rather than only the `changed` list.
		self._inspector = inspector
		#: Every target this port was ASKED for, including the ones that changed
		#: nothing -- "the handler dispatched" and "the mode moved" are different
		#: facts and a test needs both.
		self.calls: list[str] = []
		#: Targets that actually moved the mode.
		self.writes: list[str] = []
		self.fail_with: str | None = None

	def set_browse_mode(self, target: str) -> bool:
		self.calls.append(target)
		if self.fail_with is not None:
			raise StateSetError(self.fail_with)
		if self.browse_mode == target:
			return False
		self.browse_mode = target
		self.writes.append(target)
		if self._inspector is not None:
			self._inspector.reader_state = dataclasses.replace(
				self._inspector.reader_state, browse_mode=target
			)
		return True
