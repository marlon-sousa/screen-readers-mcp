# nvdaMcpBridge domain -- IndexedBuffer: shared base for the capture buffers.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: entity base, the index bookkeeping, locking and wait loop of the speech and braille buffers.
# EXTENDED BY: entities/speech_buffer.py, entities/braille_buffer.py.
# The lock is required: captures arrive on NVDA's speech thread while the session thread reads.
# Index 0 holds an empty sentinel, so the first real capture lands at index 1, as in NVDA's own NVDASpyLib.

from __future__ import annotations

import threading
from collections.abc import Callable
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
	from ..ports.clock import Clock

POLL_INTERVAL: float = 0.03


class IndexedBuffer:
	"""Subclasses supply :meth:`_sentinel` and :meth:`_render`; the base owns the lock and index reads."""

	def __init__(self, clock: Clock) -> None:
		self._clock = clock
		self._lock = threading.RLock()
		self._entries: list[Any] = [self._sentinel()]
		self._log_positions: list[int] = [0]
		# Wall-clock, for the agent to line up with other artefacts; ``_last_time`` stays monotonic.
		self._times: list[float] = [0.0]
		self._last_time: float = clock.monotonic()

	def _record(self, entry: Any, log_position: int) -> None:
		"""The parallel lists advance together; the lock is re-entrant, so callers may hold it."""
		with self._lock:
			self._entries.append(entry)
			self._log_positions.append(log_position)
			self._times.append(self._clock.time())
			self._last_time = self._clock.monotonic()

	def _sentinel(self) -> Any:
		"""Must render to ``""``."""
		raise NotImplementedError

	def _render(self, entry: Any) -> str:
		raise NotImplementedError

	def last_index(self) -> int:
		with self._lock:
			return len(self._entries) - 1

	def next_index(self) -> int:
		with self._lock:
			return len(self._entries)

	def get_last(self) -> tuple[str, int]:
		with self._lock:
			index = len(self._entries) - 1
			return self._render(self._entries[index]), index

	def time_at(self, index: int) -> float:
		"""An out-of-range index returns ``0.0``, the "no instant recorded" sentinel."""
		with self._lock:
			if 0 <= index < len(self._times):
				return self._times[index]
			return 0.0

	def log_position_at(self, index: int) -> int:
		"""An out-of-range index returns 0, the sentinel's value."""
		with self._lock:
			if 0 <= index < len(self._log_positions):
				return self._log_positions[index]
			return 0

	def entries_since(self, index: int) -> tuple[list[tuple[str, int, int, float]], int, int]:
		"""Return ``(entries, fromIndex, toIndex)``, each entry ``(text, index, logPosition, time)``.

		Empty renderings are skipped, so an entry's index cannot be inferred from ``fromIndex``.
		A negative ``index`` is clamped to 0.
		"""
		with self._lock:
			start = max(0, index)
			to_index = len(self._entries)
			entries: list[tuple[str, int, int, float]] = []
			for i in range(start, to_index):
				text = self._render(self._entries[i])
				if text and not text.isspace():
					entries.append((text, i, self._log_positions[i], self._times[i]))
			return entries, start, to_index

	def _wait(self, predicate: Callable[[], bool], timeout: float) -> bool:
		"""Checks once immediately, so a zero timeout still evaluates the current state."""
		deadline = self._clock.monotonic() + max(0.0, timeout)
		while True:
			if predicate():
				return True
			if self._clock.monotonic() >= deadline:
				return False
			self._clock.sleep(POLL_INTERVAL)
