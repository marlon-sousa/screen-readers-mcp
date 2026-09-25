# nvdaMcpBridge domain -- the SpeechSource port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port, feeding the SpeechBuffer with what NVDA said; the factory picks the mechanism per mode.
# USED BY: the hello handler starts it; the Session stops it at teardown.
# IMPLEMENTED BY: adapters/nvda_silent_speech_source.py and nvda_live_speech_source.py;
#                 tests/fakes/speech_source.py.

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Callable
from typing import TYPE_CHECKING

if TYPE_CHECKING:
	from ..entities.speech_buffer import SpeechBuffer


class SpeechSource(ABC):
	@abstractmethod
	def start(self, buffer: SpeechBuffer, log_position: Callable[[], int]) -> None:
		"""``log_position`` is called at each capture and its result passed to ``buffer.append``."""

	@abstractmethod
	def stop(self) -> None:
		"""Idempotent and never raises."""

	@abstractmethod
	def suspend(self) -> None:
		"""Stop suppressing for an interaction window. A no-op in live mode; idempotent."""

	@abstractmethod
	def resume(self) -> None:
		"""Idempotent; must never re-mute a session the silence cap has lifted."""

	@abstractmethod
	def stop_suppressing(self) -> None:
		"""Let words through to the synth while still capturing them. Idempotent."""

	@abstractmethod
	def resume_suppressing(self) -> None:
		"""Go quiet again after :meth:`stop_suppressing`. Idempotent."""

	@abstractmethod
	def is_suppressing(self) -> bool:
		"""False in live mode, in a prompt window, and after a lift."""
