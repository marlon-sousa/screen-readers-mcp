# nvdaMcpBridge tests -- FakeSpeechSource, standing in for the SpeechSource port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# emit() stands for speech no gesture caused; FakeGestureSender feeds a gesture's own speech.

from __future__ import annotations

from collections.abc import Callable
from typing import TYPE_CHECKING

from nvdaMcpBridge.domain.ports.speech_source import SpeechSource

if TYPE_CHECKING:
	from nvdaMcpBridge.domain.entities.speech_buffer import SpeechBuffer


class FakeSpeechSource(SpeechSource):
	def __init__(self, *, suppressing: bool = True) -> None:
		self.buffer: SpeechBuffer | None = None
		self.log_position: Callable[[], int] = lambda: 0
		self.started = 0
		self.stopped = 0
		self.suspended = 0
		self.resumed = 0
		#: Defaults to True: the fake stands for a silent session unless the factory says otherwise.
		self.suppressing = suppressing
		self.stopped_suppressing = 0
		self.resumed_suppressing = 0
		self.fail_stop = False

	def start(self, buffer: SpeechBuffer, log_position: Callable[[], int]) -> None:
		self.buffer = buffer
		self.log_position = log_position
		self.started += 1

	def stop(self) -> None:
		self.stopped += 1
		if self.fail_stop:
			raise RuntimeError("speech source stop failed")

	def suspend(self) -> None:
		self.suspended += 1

	def resume(self) -> None:
		self.resumed += 1

	def stop_suppressing(self) -> None:
		self.stopped_suppressing += 1
		self.suppressing = False

	def resume_suppressing(self) -> None:
		self.resumed_suppressing += 1
		self.suppressing = True

	def is_suppressing(self) -> bool:
		return self.suppressing

	def emit(self, text: str, *, finished: bool = True) -> None:
		assert self.buffer is not None, "emit before the source was started"
		# Reads the position at capture, as the real adapters do.
		self.buffer.append([text], self.log_position())
		if finished:
			self.buffer.notify_finished()
