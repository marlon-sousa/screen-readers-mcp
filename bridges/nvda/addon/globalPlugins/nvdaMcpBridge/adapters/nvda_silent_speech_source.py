# nvdaMcpBridge adapters -- NvdaSilentSpeechSource: silent-mode capture + suppress.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the SpeechSource port for SILENT mode. On pyright's
#       ignore list (imports NVDA); validated by the 9c live-NVDA checklist.
# BUILT BY: adapters/nvda_adapter_factory.py when hello asks for silent mode.
# COLLABORATORS: speech.extensions.filter_speechSequence -- a FILTER NVDA applies
#                to every speech sequence inside speak(), BEFORE it reaches the
#                synth (speech/speech.py:1096; if the filter returns an empty
#                sequence, speak() returns and nothing is synthesized).
#
# THE DESIGN (agreed with Marlon, replacing the old spy-synth swap): we do NOT
# touch the synth at all. NVDA's real synth (espeak/ibmeci/...) stays loaded and
# active, so NVDA and every other add-on keep seeing their configured synth as
# valid -- fully transparent. We register a filter that CAPTURES each sequence
# into the buffer and then returns it EMPTIED, so no audio is produced. "Restore"
# is just stop() unregistering the filter -- speech flows again instantly, with no
# synth reload that could fail. And because NVDA holds filter handlers by WEAK
# reference, if this addon ever dies the suppression lifts on its own: the tester
# can never be stranded mute. If our handler raises, NVDA keeps the original
# sequence (extensionPoints.Filter.apply swallows handler errors), so a bug here
# fails safe toward speech, not silence.
#
# NVDA holds the handler weakly, so this instance must outlive the registration --
# the AdapterSet keeps it for the session; stop() unregisters at teardown.
#
# suspend(): unregister the filter temporary, so the tester hears speech during
# an interaction window. resume(): re-register it. Both are idempotent.
# Fails safe: a resume() that never happens leaves speech on, not silence.

from __future__ import annotations

from collections.abc import Callable
from typing import TYPE_CHECKING, Any

from logHandler import log
from speech.extensions import filter_speechSequence

from ..domain.ports.speech_source import SpeechSource

if TYPE_CHECKING:
	from ..domain.entities.speech_buffer import SpeechBuffer

#: Written into NVDA's own log once per silent session (spec 0021), not once
#: per utterance -- a silent run drops speech from the log entirely (the filter
#: empties the sequence before speech.speak's own log.io line), which otherwise
#: reads, in the human's nvda.log, like an NVDA fault rather than our doing.
SUPPRESSED_MARKER = "nvdaMcpBridge: speech suppressed for this session"
RESTORED_MARKER = "nvdaMcpBridge: speech restored for this session"


class NvdaSilentSpeechSource(SpeechSource):
	"""Captures NVDA speech and suppresses it, leaving the real synth loaded."""

	def __init__(self) -> None:
		self._buffer: SpeechBuffer | None = None
		self._log_position: Callable[[], int] = lambda: 0
		self._registered = False
		#: Whether the SUPPRESSED marker was written and its pair still owed.
		#: Tracked SEPARATELY from _registered, because suspend() clears that flag
		#: for an interaction window -- so a session torn down with a window open
		#: (which teardown deliberately does NOT resume, to leave the tester
		#: audible) would otherwise write "suppressed" and never "restored",
		#: leaving the human's own nvda.log claiming a suppression that had in
		#: fact ended. That unexplained state is the exact thing the markers exist
		#: to prevent, so the pair must balance on every path.
		self._marked = False

	def start(self, buffer: SpeechBuffer, log_position: Callable[[], int]) -> None:
		self._buffer = buffer
		self._log_position = log_position
		filter_speechSequence.register(self._capture_and_suppress)
		self._registered = True
		log.info(SUPPRESSED_MARKER)
		self._marked = True

	def stop(self) -> None:
		if self._registered:
			filter_speechSequence.unregister(self._capture_and_suppress)
			self._registered = False
		if self._marked:
			log.info(RESTORED_MARKER)
			self._marked = False
		self._buffer = None

	def suspend(self) -> None:
		"""Unregister the filter so the tester hears speech during a window."""
		if self._registered:
			filter_speechSequence.unregister(self._capture_and_suppress)
			self._registered = False

	def resume(self) -> None:
		"""Re-register the filter; idempotent, safe to call at teardown."""
		if not self._registered:
			filter_speechSequence.register(self._capture_and_suppress)
			self._registered = True

	def _capture_and_suppress(self, speechSequence: Any) -> Any:
		# Runs on NVDA's main thread (inside speak()). Capture the words, then
		# return an empty sequence so speak() stops before the synth.
		buffer = self._buffer
		if buffer is not None and speechSequence:
			buffer.append(speechSequence, self._log_position())
		return []
