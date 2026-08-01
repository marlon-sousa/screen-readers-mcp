# nvdaMcpBridge domain -- the SpeechSource port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: domain port. Whatever feeds the speech buffer with what NVDA "said".
# USED BY: the Session controller (starts it at hello, stops it at teardown).
# IMPLEMENTED BY: adapters/nvda_*.py in session C (silent: the spy synth's
#                 post_speech; live: the pre_speechQueued hook);
#                 tests/fakes/speech_source.py FakeSpeechSource.
#
# The Session never knows WHICH capture mechanism is running -- only that it can
# be started against a buffer and stopped. The mode-specific choice is the
# AdapterFactory's, made after hello reveals the mode.

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Callable
from typing import TYPE_CHECKING

if TYPE_CHECKING:
	from ..entities.speech_buffer import SpeechBuffer


class SpeechSource(ABC):
	"""Feeds captured speech sequences into a :class:`SpeechBuffer`."""

	@abstractmethod
	def start(self, buffer: SpeechBuffer, log_position: Callable[[], int]) -> None:
		"""Begin capturing into ``buffer`` (register the hook / spy synth).

		``log_position`` returns the journal's current append position; each
		capture calls it at the moment of capture and passes the result to
		``buffer.append`` (spec 0021), so a ring entry can later be placed on the
		log's timeline. The buffer itself never learns the journal exists.
		"""

	@abstractmethod
	def stop(self) -> None:
		"""Stop capturing. Idempotent and never raises -- teardown calls it in a guard."""

	@abstractmethod
	def suspend(self) -> None:
		"""Temporarily stop suppressing speech (unregister the filter).

		In ``silent`` mode this unregisters the filter so the human hears
		everything during an interaction window. In ``live`` mode it is a no-op
		because nothing was suppressed. Idempotent, like ``stop``.
		"""

	@abstractmethod
	def resume(self) -> None:
		"""Re-suppress speech after ``suspend`` (re-register the filter).

		Idempotent, so a teardown that calls it on a source that was never
		suspended is safe. Fails in the safe direction: a ``resume`` that never
		happens leaves the tester with speech, not silence.
		"""
