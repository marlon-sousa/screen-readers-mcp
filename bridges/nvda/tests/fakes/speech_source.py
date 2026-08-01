# nvdaMcpBridge tests -- FakeSpeechSource, standing in for the SpeechSource port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# FAKES: domain/ports/speech_source.py
#
# Keeps the buffer it was started with and exposes ``emit`` for speech NOT caused
# by a gesture -- background chatter, focus noise -- so a test can prove index
# bookmarks separate that from a gesture's own response. Gesture-driven speech is
# fed by FakeGestureSender (which reads this source's buffer), mirroring
# production, where pressing a key makes NVDA speak through the real speech source.

from __future__ import annotations

from collections.abc import Callable
from typing import TYPE_CHECKING

from nvdaMcpBridge.domain.ports.speech_source import SpeechSource

if TYPE_CHECKING:
	from nvdaMcpBridge.domain.entities.speech_buffer import SpeechBuffer


class FakeSpeechSource(SpeechSource):
	"""Records start/stop/suspend/resume and lets a test inject arbitrary speech."""

	def __init__(self) -> None:
		self.buffer: SpeechBuffer | None = None
		self.log_position: Callable[[], int] = lambda: 0
		self.started = 0
		self.stopped = 0
		self.suspended = 0
		self.resumed = 0
		#: Set by a test to prove teardown's guard runs restore even when an
		#: earlier teardown step (a source stop) raises.
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

	def emit(self, text: str, *, finished: bool = True) -> None:
		"""Inject a spoken line (as a one-string speech sequence)."""
		assert self.buffer is not None, "emit before the source was started"
		# Reads the position AT CAPTURE, as the real adapters do (spec 0021).
		# A fake that passed 0 here would let a broken wiring pass every test
		# above it -- the same gap FakeLogCapture's level bookkeeping warns about.
		self.buffer.append([text], self.log_position())
		if finished:
			self.buffer.notify_finished()
