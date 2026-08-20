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

		**It must not re-mute a session the silence cap has lifted** (spec 0032
		Part 3). This is invisible at the call site -- ``waitForUserReply`` calls
		``resume`` when a prompt is answered, and if a lift happened before or
		during that prompt, a naive re-register silently re-mutes the human the cap
		had just rescued: the exact harm, reintroduced by the recovery path. What
		``resume`` restores is therefore whichever of the two REGISTERED states was
		in force, suppressing or passing through -- never suppression unasked.
		"""

	@abstractmethod
	def stop_suppressing(self) -> None:
		"""Let words through to the synth while still capturing them (spec 0032).

		The third state of a speech source, and the whole shape of the silence
		cap's remedy. ``suspend`` is the wrong tool here: it UNREGISTERS the
		filter, and that filter is where capture happens, so suspending would give
		the human their sound back by taking the agent's evidence away. Nothing
		about the human's problem requires that trade.

		Here the filter stays registered, the buffer keeps filling, and the
		sequence is returned INTACT instead of emptied -- so ``getSpeech`` answers
		with the same entries, the same indices and the same timestamps as before,
		and the words also reach the speakers.

		Idempotent, and a no-op in live mode (nothing was ever suppressed).
		"""

	@abstractmethod
	def resume_suppressing(self) -> None:
		"""Go quiet again after :meth:`stop_suppressing`, and mark it (spec 0032).

		A lifted session may re-arm: the agent narrates, the ordinary flow resumes,
		and a fresh bounded window starts from zero. Idempotent, and a no-op in
		live mode.
		"""

	@abstractmethod
	def is_suppressing(self) -> bool:
		"""Whether words are being withheld from the human RIGHT NOW.

		False in live mode, false while a prompt window has the filter suspended,
		and false after the silence cap has lifted -- so this is the honest answer
		to "can the person at this machine hear it?", not "was this session opened
		silent". ``status`` reports it, which is how a lift is discoverable by
		asking (spec 0032 Part 5).
		"""
