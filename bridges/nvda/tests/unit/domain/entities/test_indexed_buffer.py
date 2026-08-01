# Unit tests for domain/entities/indexed_buffer.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# The base's own contract -- index bookkeeping, the half-open range reads and
# the wait loop -- exercised through a minimal concrete subclass, so it is
# tested once here rather than incidentally through whichever subclass happened
# to be handy. SpeechBuffer / BrailleBuffer then test only what they add.

from __future__ import annotations

from typing import Any

import pytest
from fakes.clock import FakeClock
from nvdaMcpBridge.domain.entities.indexed_buffer import IndexedBuffer


class _StubBuffer(IndexedBuffer):
	"""The smallest possible concrete buffer: entries are plain strings."""

	def _sentinel(self) -> Any:
		return ""

	def _render(self, entry: Any) -> str:
		return entry if isinstance(entry, str) else ""

	def append(self, text: str, log_position: int = 0) -> None:
		with self._lock:
			self._entries.append(text)
			self._log_positions.append(log_position)
			self._last_time = self._clock.monotonic()


@pytest.fixture
def buffer(clock: FakeClock) -> _StubBuffer:
	return _StubBuffer(clock)


# -- index bookkeeping --------------------------------------------------------


def test_starts_at_sentinel_index_zero(buffer: _StubBuffer) -> None:
	assert buffer.last_index() == 0
	assert buffer.next_index() == 1
	# The sentinel renders empty, so the last entry reads as "".
	assert buffer.get_last() == ("", 0)


def test_append_advances_indices_and_next_index_is_the_bookmark(buffer: _StubBuffer) -> None:
	bookmark = buffer.next_index()
	buffer.append("one")
	assert bookmark == 1
	assert buffer.last_index() == 1
	assert buffer.next_index() == 2
	assert buffer.get_last() == ("one", 1)


# -- range reads --------------------------------------------------------------


def test_entries_since_returns_half_open_range_and_drops_empties(buffer: _StubBuffer) -> None:
	start = buffer.next_index()
	buffer.append("one")
	buffer.append("")  # empty entry is skipped
	buffer.append("two")
	entries, from_index, to_index = buffer.entries_since(start)
	assert [e[0] for e in entries] == ["one", "two"]
	assert (from_index, to_index) == (1, 4)


def test_each_entry_carries_the_index_it_actually_occupies(buffer: _StubBuffer) -> None:
	# Why the entry has to carry its own index (spec 0021): the empty entry at 2 is
	# dropped, so "two" is the SECOND item in the list but index 3. A caller could
	# not have derived that from fromIndex, which is what made a parallel list of
	# positions -- or a single position on a joined blob -- unusable.
	buffer.append("one")
	buffer.append("")
	buffer.append("two")
	entries, _from_index, _to_index = buffer.entries_since(1)
	assert [(text, index) for text, index, _pos in entries] == [("one", 1), ("two", 3)]


def test_each_entry_carries_the_log_position_it_was_captured_at(buffer: _StubBuffer) -> None:
	buffer.append("one", 17)
	buffer.append("two", 42)
	entries, _from_index, _to_index = buffer.entries_since(1)
	assert [pos for _text, _index, pos in entries] == [17, 42]


def test_an_entry_appended_without_a_position_reports_zero(buffer: _StubBuffer) -> None:
	# The position is a plain default, not a required argument: a capture path that
	# has no journal to ask (or a test that does not care) still appends.
	buffer.append("one")
	assert buffer.entries_since(1)[0][0][2] == 0


def test_entries_since_clamps_a_stale_or_negative_bookmark(buffer: _StubBuffer) -> None:
	buffer.append("a")
	# A bookmark from a previous session must not raise.
	assert buffer.entries_since(-5)[1] == 0
	assert buffer.entries_since(999) == ([], 999, 2)


# -- the wait loop ------------------------------------------------------------


def test_wait_returns_immediately_when_already_true(clock: FakeClock, buffer: _StubBuffer) -> None:
	assert buffer._wait(lambda: True, timeout=5.0) is True  # type: ignore[attr-defined]
	assert clock.sleeps == []  # never had to wait


def test_wait_gives_up_at_the_deadline_without_sleeping_for_real(
	clock: FakeClock, buffer: _StubBuffer
) -> None:
	assert buffer._wait(lambda: False, timeout=5.0) is False  # type: ignore[attr-defined]
	# The fake clock advanced past the deadline via instant sleeps.
	assert clock.monotonic() >= 5.0


def test_wait_evaluates_once_even_with_a_zero_timeout(buffer: _StubBuffer) -> None:
	calls: list[int] = []

	def _predicate() -> bool:
		calls.append(1)
		return True

	assert buffer._wait(_predicate, timeout=0.0) is True  # type: ignore[attr-defined]
	assert len(calls) == 1
