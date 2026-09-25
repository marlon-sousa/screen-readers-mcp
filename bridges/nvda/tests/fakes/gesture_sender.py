# nvdaMcpBridge tests -- FakeGestureSender, standing in for the GestureSender port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# On a scripted press, feeds the scripted speech into the FakeSpeechSource's buffer, as NVDA's speech would.

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import TYPE_CHECKING

from nvdaMcpBridge.domain.ports.gesture_sender import GestureError, GestureSender

if TYPE_CHECKING:
	from .speech_source import FakeSpeechSource


class FakeGestureSender(GestureSender):
	def __init__(
		self,
		source: FakeSpeechSource,
		*,
		reject: Sequence[str] | None = None,
		speech: Mapping[str, Sequence[str]] | None = None,
	) -> None:
		self._source = source
		self._reject = set(reject or ())
		self._speech = {gid: list(lines) for gid, lines in (speech or {}).items()}
		self.pressed: list[str] = []
		#: Ids that raise a non-GestureError exception.
		self.boom: set[str] = set()

	def press(self, gesture_id: str) -> None:
		if gesture_id in self._reject:
			raise GestureError(f"unknown gesture: {gesture_id!r}")
		if gesture_id in self.boom:
			raise RuntimeError(f"unexpected fault pressing {gesture_id!r}")
		self.pressed.append(gesture_id)
		lines = self._speech.get(gesture_id)
		if not lines:
			return
		buffer = self._source.buffer
		assert buffer is not None, "a scripted gesture spoke before the source was started"
		for line in lines:
			buffer.append([line])
		buffer.notify_finished()
