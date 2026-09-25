# nvdaMcpBridge adapters -- NvdaSilentSpeechSource: silent-mode capture + suppress.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing SpeechSource for silent mode: a filter_speechSequence handler captures each
#       sequence and returns it empty, and the synth is never swapped.
# BUILT BY: adapters/nvda_adapter_factory.py.
# NVDA holds filter handlers weakly, so suppression lifts if the add-on dies, and this instance must
# outlive its registration. In NVDA 2026.1 a raising filter handler leaves the sequence intact, so a bug
# here fails toward speech.
# Registered and suppressing are independent: the silence cap stops suppressing while capture continues,
# and suspend() unregisters the filter for an interaction window.
# Emptying a sequence also deletes its callback commands, and in NVDA 2026.1 say all advances only
# through them, so the callbacks are queued and run here; run inline they would recurse through speak().
# Passing the callbacks on without words is not reliable: in NVDA 2026.1 espeak, oneCore, RHVoice, ibmeci
# and "No speech" may report no index for a text-free utterance.

from __future__ import annotations

from collections.abc import Callable
from typing import TYPE_CHECKING, Any

import queueHandler
from logHandler import log
from speech.commands import BaseCallbackCommand, BeepCommand, WaveFileCommand
from speech.extensions import filter_speechSequence

from ..domain.ports.speech_source import SpeechSource

if TYPE_CHECKING:
	from ..domain.entities.speech_buffer import SpeechBuffer

#: Logged once per silent session, since suppressed speech is otherwise missing from nvda.log unexplained.
SUPPRESSED_MARKER = "nvdaMcpBridge: speech suppressed for this session"
RESTORED_MARKER = "nvdaMcpBridge: speech restored for this session"

#: Logged before the suppressed/restored pair when the silence cap was the cause.
CAP_LIFTED_MARKER = "nvdaMcpBridge: silence cap reached -- speech is passing through, capture continues"
CAP_RESUPPRESSED_MARKER = "nvdaMcpBridge: speech suppression re-armed after the silence cap lifted it"


class NvdaSilentSpeechSource(SpeechSource):
	def __init__(self) -> None:
		self._buffer: SpeechBuffer | None = None
		self._log_position: Callable[[], int] = lambda: 0
		self._registered = False
		#: Whether a SUPPRESSED marker still owes its RESTORED pair; separate from _registered because a
		#: teardown with an interaction window open leaves the filter unregistered.
		self._marked = False
		#: Whether the filter empties what it captures; the silence cap clears it, the filter stays.
		self._suppressing = True

	def start(self, buffer: SpeechBuffer, log_position: Callable[[], int]) -> None:
		self._buffer = buffer
		self._log_position = log_position
		filter_speechSequence.register(self._capture_and_suppress)
		self._registered = True
		self._suppressing = True
		self._mark_suppressed()

	def stop(self) -> None:
		if self._registered:
			filter_speechSequence.unregister(self._capture_and_suppress)
			self._registered = False
		self._mark_restored()
		self._buffer = None

	def suspend(self) -> None:
		if self._registered:
			filter_speechSequence.unregister(self._capture_and_suppress)
			self._registered = False

	def resume(self) -> None:
		"""Never touches _suppressing, so it cannot re-mute a session the silence cap has lifted."""
		if not self._registered:
			filter_speechSequence.register(self._capture_and_suppress)
			self._registered = True

	def stop_suppressing(self) -> None:
		if not self._suppressing:
			return
		self._suppressing = False
		log.info(CAP_LIFTED_MARKER)
		self._mark_restored()

	def resume_suppressing(self) -> None:
		if self._suppressing:
			return
		self._suppressing = True
		log.info(CAP_RESUPPRESSED_MARKER)
		self._mark_suppressed()

	def is_suppressing(self) -> bool:
		"""A suspended filter withholds nothing either."""
		return self._registered and self._suppressing

	def _mark_suppressed(self) -> None:
		if self._marked:
			return
		log.info(SUPPRESSED_MARKER)
		self._marked = True

	def _mark_restored(self) -> None:
		if not self._marked:
			return
		log.info(RESTORED_MARKER)
		self._marked = False

	def _capture_and_suppress(self, speechSequence: Any) -> Any:
		# Runs on NVDA's main thread, inside speak().
		buffer = self._buffer
		if buffer is not None and speechSequence:
			buffer.append(speechSequence, self._log_position())
		if not self._suppressing:
			# NVDA runs a passed-through sequence's callbacks; running them here too double-advances say all.
			return speechSequence
		self._advance_callbacks(speechSequence)
		return []

	def _advance_callbacks(self, speechSequence: Any) -> None:
		"""Beeps and wave files are skipped, since running them would make a sound in a silent session."""
		for item in speechSequence or ():
			if isinstance(item, (BeepCommand, WaveFileCommand)):
				continue
			if isinstance(item, BaseCallbackCommand):
				queueHandler.queueFunction(queueHandler.eventQueue, self._run, item)

	def _run(self, command: Any) -> None:
		# An exception escaping onto the event queue would take down unrelated work.
		try:
			command.run()
		except Exception:
			log.exception("nvdaMcpBridge: speech callback failed in silent mode")
