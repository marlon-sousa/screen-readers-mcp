# nvdaMcpBridge domain -- SpeechBuffer: indexed capture of what NVDA speaks.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: entity.
# FED BY: the SpeechSource port's implementation, calling append.
# READ BY: the speech command handlers.

from __future__ import annotations

from collections.abc import Callable
from typing import TYPE_CHECKING, Any

from .indexed_buffer import IndexedBuffer
from .speech_text import join_speech

if TYPE_CHECKING:
	from ..ports.clock import Clock
	from ..ports.continuous_read import ContinuousRead

# Neither capture mode has an exact finish signal, so speech counts as finished after this much quiet.
# NVDA 2026.1 finishes a keystroke's speech about 124 ms after the gesture, well inside this window.
SPEECH_FINISHED_SECONDS: float = 1.0

# Bounds how long a claimed continuous read may hold the settle open, so a wrong port answer cannot hang.
# NVDA 2026.1 with ibmeci measured 1.8 to 2.0 s between say-all chunks.
CONTINUOUS_READ_STALE_SECONDS: float = 6.0


class SpeechBuffer(IndexedBuffer):
	"""``exact_finish`` is left false in both capture modes, which use the elapsed-time heuristic."""

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
		# None means no continuous read is ever in progress.
		self._continuous_read: ContinuousRead | None = continuous_read

	def _sentinel(self) -> Any:
		return [""]

	def _render(self, entry: Any) -> str:
		return join_speech(entry)

	def set_observer(self, observer: Callable[[str], None] | None) -> None:
		"""The observer is called outside the lock."""
		self._observer = observer

	def append(self, sequence: Any, log_position: int = 0) -> None:
		"""Called from NVDA's speech thread."""
		with self._lock:
			self._record(sequence, log_position)
			self._speaking = True
			text = join_speech(sequence)
		if self._observer is not None and text:
			self._observer(text)

	def notify_finished(self) -> None:
		with self._lock:
			self._speaking = False

	def index_of(self, text: str, after_index: int | None = None) -> int:
		"""``after_index`` is an inclusive left edge, clamped to 0. Returns ``-1`` when not found."""
		first = 0 if after_index is None else max(0, after_index)
		with self._lock:
			for offset, entry in enumerate(self._entries[first:]):
				if text in self._render(entry):
					return first + offset
		return -1

	def wait_for(self, text: str, after_index: int | None, timeout: float) -> tuple[bool, int, str]:
		"""Returns ``(found, index, text)``; on a miss, ``index`` is the current :meth:`next_index`."""
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
		"""Return :meth:`entries_since`'s triple once anything arrives or ``grace`` elapses.

		Returns early, so an utterance still in flight is left for the next read. An empty result means
		nothing had arrived by then, not that nothing will.
		"""

		def _arrived() -> bool:
			entries, _from_index, _to_index = self.entries_since(index)
			return bool(entries)

		self._wait(_arrived, grace)
		return self.entries_since(index)

	def wait_to_finish(self, timeout: float) -> bool:
		return self._wait(self._has_finished, timeout)

	def _has_finished(self) -> bool:
		# Outside the lock, so a port call never holds the mutex append() takes on NVDA's thread.
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
