# nvdaMcpBridge domain -- SpeechBuffer: indexed capture of what NVDA speaks.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: entity. The bridge's central subject matter.
# FED BY: the SpeechSource port's implementation (the spy synth in silent mode,
#         the pre_speechQueued hook in live mode) calling append/notify_finished.
# READ BY: the Session controller, answering getSpeech / waitForSpeech / ...
# DEPENDS ON: the Clock port (injected via IndexedBuffer).

from __future__ import annotations

from collections.abc import Callable
from typing import TYPE_CHECKING, Any

from .indexed_buffer import IndexedBuffer

if TYPE_CHECKING:
	from ..ports.clock import Clock
	from ..ports.continuous_read import ContinuousRead

#: Neither mode has an exact "speech finished" signal (spec 0008 removed the spy
#: synth; silent mode suppresses at the speak() filter, so no synth ever runs),
#: so both treat speech as finished once this many seconds pass with no new
#: sequence -- NVDASpyLib's ``SPEECH_HAS_FINISHED_SECONDS``.
#:
#: MEASURED 2026-08-03, and the number turns out not to matter: NVDA finishes
#: producing a keystroke's speech ~124 ms after the gesture, while an agent's
#: tool round trip is ~2.6 s. So by the time waitForSpeechToFinish arrives this
#: window has ALWAYS already expired, and the call returns from a stale
#: ``_last_time`` without waiting on anything. Shortening it buys nothing --
#: it was never being paid. See ROADMAP entry 11.9.
SPEECH_FINISHED_SECONDS: float = 1.0

#: A ceiling on how long a claimed continuous read may hold the settle open with
#: nothing arriving. The ContinuousRead port is the reader's own account and is
#: normally right -- but this project has now shipped one version of that port
#: that was WRONG in the direction that never clears (it read object liveness
#: rather than reader state, and a settle built on it never settled). A wrong
#: answer that expires is an imprecision; a wrong answer that does not is a hang,
#: and only one of those is worth risking on a reader we do not control.
#:
#: Set well above the inter-chunk gap MEASURED live on 2026-08-18 -- 1.8 to 2.0 s
#: for every one of thirty lines, under ibmeci -- so a genuine read is never cut
#: short by it. That measurement is also why SPEECH_FINISHED_SECONDS alone could
#: never work here: every gap in that say-all exceeded it.
CONTINUOUS_READ_STALE_SECONDS: float = 6.0


def _join_speech(sequence: Any) -> str:
	"""Join the plain-string parts of a speech sequence with a separating space.

	NVDA speech sequences interleave ``str`` fragments with ``SpeechCommand``
	objects (pitch, index, callbacks, ...). Only the strings are spoken words,
	so those are all we capture.

	The parts are joined with a SPACE, not concatenated. A sequence's fragments
	are separate utterances -- a name, a role, a position, an accelerator letter
	-- and running them together produces text no reader can segment:
	``"Move" + "indisponivel" + "m"`` came out as ``Moveindisponivelm``, and
	``"Google Chrome" + "17 de 37"`` as ``Google Chrome17 de 37``. The join is
	the only place the boundary is known, so it is the only place it can be kept.
	"""
	if not isinstance(sequence, (list, tuple)):
		return ""
	parts = [c.strip() for c in sequence if isinstance(c, str)]  # pyright: ignore[reportUnknownVariableType]
	return " ".join(p for p in parts if p)


class SpeechBuffer(IndexedBuffer):
	"""Indexed capture of NVDA speech sequences with wait-for / wait-to-finish.

	``exact_finish`` selects how "speech has finished" is decided. Since spec 0008
	removed the spy synth there is no exact signal in either mode, so both leave
	it false and fall back to the elapsed-time heuristic.
	"""

	def __init__(
		self,
		clock: Clock,
		*,
		exact_finish: bool = False,
		continuous_read: ContinuousRead | None = None,
	) -> None:
		super().__init__(clock)
		self.exact_finish: bool = exact_finish
		self._speaking: bool = False
		self._observer: Callable[[str], None] | None = None
		#: Optional, and None means "assume not" -- so a reader whose bridge has
		#: no way to see a continuous read keeps exactly today's behaviour.
		self._continuous_read: ContinuousRead | None = continuous_read

	def _sentinel(self) -> Any:
		return [""]

	def _render(self, entry: Any) -> str:
		return _join_speech(entry)

	def set_observer(self, observer: Callable[[str], None] | None) -> None:
		"""Register a callback fired (outside the lock) for each appended text.

		The Session wires this to the Transcript port so captured speech is
		logged bridge-side even if the agent never fetches it.
		"""
		self._observer = observer

	def append(self, sequence: Any, log_position: int = 0) -> None:
		"""Record a captured speech sequence; called from NVDA's speech thread.

		``log_position`` is the journal's append position at the moment of
		capture (spec 0021) -- a plain value from the caller, so this buffer
		never learns the journal exists. Production callers (the speech source
		adapters) always pass the real one; the default lets tests that do not
		care about the join omit it.
		"""
		with self._lock:
			self._record(sequence, log_position)
			self._speaking = True
			text = _join_speech(sequence)
		if self._observer is not None and text:
			self._observer(text)

	def notify_finished(self) -> None:
		"""Exact "speech finished" signal (silent mode: ``synthDoneSpeaking``)."""
		with self._lock:
			self._speaking = False

	def index_of(self, text: str, after_index: int | None = None) -> int:
		"""First index at/after ``after_index`` whose text contains ``text``.

		``after_index`` is exclusive (search starts at ``after_index + 1``),
		matching NVDASpyLib. Returns ``-1`` when not found.
		"""
		first = 0 if after_index is None else after_index + 1
		with self._lock:
			for offset, entry in enumerate(self._entries[first:]):
				if text in self._render(entry):
					return first + offset
		return -1

	def wait_for(self, text: str, after_index: int | None, timeout: float) -> tuple[bool, int, str]:
		"""Block until ``text`` is spoken after ``after_index`` or ``timeout``.

		Returns ``(found, index, text)``. On a miss, ``index`` is the current
		:meth:`next_index` (a fresh bookmark) and ``text`` is empty.
		"""
		found_index = -1

		def _seen() -> bool:
			nonlocal found_index
			found_index = self.index_of(text, after_index)
			return found_index >= 0

		if self._wait(_seen, timeout):
			with self._lock:
				return True, found_index, self._render(self._entries[found_index])
		return False, self.next_index(), ""

	def collect_since(self, index: int, grace: float) -> tuple[list[tuple[str, int, int, float]], int, int]:
		"""Entries from ``index`` that arrive within ``grace`` seconds; then stop.

		The grace window of spec 0025, and the whole reason it is a different
		primitive from :meth:`wait_to_finish`. That one asks "has speech
		STOPPED?", which cannot be answered at the moment it is asked -- silence
		before speech starts and silence after it ends are the same observable,
		so no constant makes the answer true. This asks "has speech STARTED?",
		and returns what had arrived by an instant the caller chose. An empty
		result is therefore a fact ("nothing by then"), not a claim ("nothing").

		Returns exactly :meth:`entries_since`'s triple, so a caller reports the
		half-open range the same way it always did and resumes from ``toIndex``.

		Returns EARLY as soon as anything renders non-empty, because the common
		case is one announcement ~124 ms after a keystroke and waiting out the
		rest of the window buys nothing. The cost of that choice is stated
		rather than hidden: an utterance still in flight when the first one
		lands is left for the next read, which the caller can always take,
		since the range it was handed says exactly where to resume.

		``grace <= 0`` is a legitimate opt-out -- it reads the buffer as it
		stands and never sleeps, which is the pre-0025 behaviour.
		"""

		def _arrived() -> bool:
			entries, _from_index, _to_index = self.entries_since(index)
			return bool(entries)

		self._wait(_arrived, grace)
		return self.entries_since(index)

	def wait_to_finish(self, timeout: float) -> bool:
		"""Block until NVDA has stopped speaking, or ``timeout`` elapses."""
		return self._wait(self._has_finished, timeout)

	def _has_finished(self) -> bool:
		# Asked FIRST, and outside the lock. A continuous read that is part-way
		# through is not finished however long the gap since the last chunk has
		# been -- the gap IS the read, waiting on audio for the chunk it just
		# handed over. Reading it before taking the lock keeps a port call off
		# the buffer's own mutex, which append() takes from NVDA's thread.
		if self._continuous_read is not None and self._continuous_read.in_progress():
			with self._lock:
				quiet_for = self._clock.monotonic() - self._last_time
			# Believed, but not forever: see CONTINUOUS_READ_STALE_SECONDS.
			if quiet_for <= CONTINUOUS_READ_STALE_SECONDS:
				return False
		with self._lock:
			if self.exact_finish:
				return not self._speaking
			return (self._clock.monotonic() - self._last_time) > SPEECH_FINISHED_SECONDS
