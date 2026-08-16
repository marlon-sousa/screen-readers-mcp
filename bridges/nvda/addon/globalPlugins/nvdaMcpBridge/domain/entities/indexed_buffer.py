# nvdaMcpBridge domain -- IndexedBuffer: shared base for the capture buffers.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: entity base -- index bookkeeping + thread safety + the wait loop.
# EXTENDED BY: entities/speech_buffer.py, entities/braille_buffer.py.
# DEPENDS ON: the Clock port (injected), nothing else.
#
# A stdlib-only port of the buffer half of NVDA's own ``NVDASpyLib``
# (``tests/system/libraries/SystemTestSpy/speechSpyGlobalPlugin.py``). Captures
# land in an append-only, index-addressed list guarded by an RLock, because the
# capture callback runs on NVDA's speech thread while the session thread reads.
#
# Index-based access -- "everything since index N", "wait for text after index
# N" -- is what makes assertions race-free: the agent bookmarks an index
# (``getNextSpeechIndex``), sends a gesture, then reads/waits from that bookmark,
# so background chatter that arrived earlier can never be mistaken for the
# response to its action.
#
# Index convention (kept identical to NVDASpyLib): a buffer starts with one
# empty sentinel entry at index 0, so ``[-1]`` is always valid and the first
# real capture lands at index 1. ``next_index()`` is the index the next capture
# will occupy; it is the bookmark an agent takes before an action.

from __future__ import annotations

import threading
from collections.abc import Callable
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
	from ..ports.clock import Clock

#: Poll cadence for the wait loops. Small enough to feel instant, large enough
#: not to spin. A fake clock makes ``sleep`` an instant advance, so tests that
#: exercise these loops never actually pause.
POLL_INTERVAL: float = 0.03


class IndexedBuffer:
	"""Common index bookkeeping for the speech and braille buffers.

	Subclasses supply :meth:`_sentinel` (the empty entry at index 0) and
	:meth:`_render` (entry -> displayable string) and decide what an entry is;
	this base owns the lock, append timing, and the index-range reads.
	"""

	def __init__(self, clock: Clock) -> None:
		self._clock = clock
		self._lock = threading.RLock()
		self._entries: list[Any] = [self._sentinel()]
		#: The journal position captured alongside each entry, same length and
		#: index as ``_entries`` (spec 0021) -- a plain value handed in by
		#: whoever calls ``append``, so this buffer never learns the journal
		#: exists.
		self._log_positions: list[int] = [0]
		#: Wall-clock epoch seconds captured alongside each entry, same length
		#: and index as ``_entries`` (spec 0028). Stored as a NUMBER: rendering
		#: it is a controller's job, so this entity stays free of presentation.
		#:
		#: Distinct from ``_last_time`` below, which is MONOTONIC and stays that
		#: way. The two answer different questions and must not be merged: the
		#: heuristic measures an elapsed duration and has to survive a clock
		#: correction, while a reported stamp has to line up against artefacts
		#: stamped by somebody else.
		self._times: list[float] = [0.0]
		self._last_time: float = clock.monotonic()

	def _record(self, entry: Any, log_position: int) -> None:
		"""Append *entry* with the bookkeeping every subclass owes it.

		The three parallel lists and the heuristic's timestamp must advance
		together or an index means different things in each. Spec 0028 found
		them being maintained in three separate ``append`` implementations --
		speech, braille, and the test double -- and adding one field to all
		three missed one, which is the whole argument for this method existing.
		Subclasses decide WHETHER and WHAT to record; this decides what
		recording entails.

		The lock is re-entrant, so a caller already holding it (both real
		buffers do, to make their checks and their append one atomic step) may
		call this without deadlocking.
		"""
		with self._lock:
			self._entries.append(entry)
			self._log_positions.append(log_position)
			# Two clocks, two jobs: the wall-clock stamp is what an agent reads
			# back and must line up with artefacts stamped elsewhere; the
			# monotonic one drives the still-speaking heuristic and must survive
			# a clock correction (spec 0028).
			self._times.append(self._clock.time())
			self._last_time = self._clock.monotonic()

	def _sentinel(self) -> Any:
		"""The empty entry seeded at index 0. Must render to ``""``."""
		raise NotImplementedError

	def _render(self, entry: Any) -> str:
		raise NotImplementedError

	def last_index(self) -> int:
		"""Index of the most recent entry (0 when only the sentinel is present)."""
		with self._lock:
			return len(self._entries) - 1

	def next_index(self) -> int:
		"""Index the next captured entry will occupy; the agent's bookmark."""
		with self._lock:
			return len(self._entries)

	def get_last(self) -> tuple[str, int]:
		"""``(rendered text, index)`` of the most recent entry."""
		with self._lock:
			index = len(self._entries) - 1
			return self._render(self._entries[index]), index

	def time_at(self, index: int) -> float:
		"""Wall-clock epoch recorded for the entry at *index*, or ``0.0``.

		The single-entry reads (``getLastSpeech``, ``waitForSpeech``) get their
		stamp through here rather than through the entry tuples, exactly as they
		already do for the journal coordinate. An out-of-range index reports the
		sentinel's ``0.0`` so a stale bookmark can never raise, and ``0.0``
		renders as an empty string rather than as 1970 (spec 0028).
		"""
		with self._lock:
			if 0 <= index < len(self._times):
				return self._times[index]
			return 0.0

	def log_position_at(self, index: int) -> int:
		"""The journal position recorded for the entry at *index*, or 0.

		The single-entry reads (``getLastSpeech``, ``waitForSpeech``) get their
		coordinate through here rather than through the entry tuples, since they
		already know the index they matched. An out-of-range index reports 0 --
		the sentinel's value -- so a stale bookmark can never raise (spec 0021).
		"""
		with self._lock:
			if 0 <= index < len(self._log_positions):
				return self._log_positions[index]
			return 0

	def entries_since(self, index: int) -> tuple[list[tuple[str, int, int, float]], int, int]:
		"""Non-empty rendered entries from ``index`` to now, each with its own index.

		Returns ``(entries, fromIndex, toIndex)``: ``fromIndex``/``toIndex`` span
		the whole half-open range ``[fromIndex, toIndex)`` requested, exactly as
		before, but each surviving entry is now a
		``(text, index, logPosition, time)`` tuple carrying the index it
		actually occupies -- so which entry
		rendered which line is explicit rather than inferred. An empty rendering
		is skipped, same as the old joined text was; the index gap that leaves
		is exactly why a position could not be recovered from ``fromIndex`` alone
		(spec 0021). A negative or out-of-range ``index`` is clamped into range
		so a stale bookmark can never raise.
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
		"""Poll ``predicate`` until it is true or ``timeout`` seconds elapse.

		Checks once immediately (so a zero timeout still evaluates the current
		state), then sleeps the clock between polls. Returns whether it was met.
		"""
		deadline = self._clock.monotonic() + max(0.0, timeout)
		while True:
			if predicate():
				return True
			if self._clock.monotonic() >= deadline:
				return False
			self._clock.sleep(POLL_INTERVAL)
