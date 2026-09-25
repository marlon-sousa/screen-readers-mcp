# Unit tests for domain/entities/indexed_buffer.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

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
		self._record(text, log_position)

	def heuristic_mark(self) -> float:
		"""The base's monotonic mark, exposed so a test can assert it advances."""
		return self._last_time


@pytest.fixture
def buffer(clock: FakeClock) -> _StubBuffer:
	return _StubBuffer(clock)


def test_starts_at_sentinel_index_zero(buffer: _StubBuffer) -> None:
	assert buffer.last_index() == 0
	assert buffer.next_index() == 1
	assert buffer.get_last() == ("", 0)


def test_append_advances_indices_and_next_index_is_the_bookmark(buffer: _StubBuffer) -> None:
	bookmark = buffer.next_index()
	buffer.append("one")
	assert bookmark == 1
	assert buffer.last_index() == 1
	assert buffer.next_index() == 2
	assert buffer.get_last() == ("one", 1)


def test_entries_since_returns_half_open_range_and_drops_empties(buffer: _StubBuffer) -> None:
	start = buffer.next_index()
	buffer.append("one")
	buffer.append("")
	buffer.append("two")
	entries, from_index, to_index = buffer.entries_since(start)
	assert [e[0] for e in entries] == ["one", "two"]
	assert (from_index, to_index) == (1, 4)


def test_each_entry_carries_the_index_it_actually_occupies(buffer: _StubBuffer) -> None:
	buffer.append("one")
	buffer.append("")
	buffer.append("two")
	entries, _from_index, _to_index = buffer.entries_since(1)
	assert [(text, index) for text, index, _pos, _at in entries] == [("one", 1), ("two", 3)]


def test_each_entry_carries_the_log_position_it_was_captured_at(buffer: _StubBuffer) -> None:
	buffer.append("one", 17)
	buffer.append("two", 42)
	entries, _from_index, _to_index = buffer.entries_since(1)
	assert [pos for _text, _index, pos, _at in entries] == [17, 42]


def test_an_entry_appended_without_a_position_reports_zero(buffer: _StubBuffer) -> None:
	# The position is a plain default, not a required argument: a capture path that
	buffer.append("one")
	assert buffer.entries_since(1)[0][0][2] == 0


def test_entries_since_clamps_a_stale_or_negative_bookmark(buffer: _StubBuffer) -> None:
	buffer.append("a")
	assert buffer.entries_since(-5)[1] == 0
	assert buffer.entries_since(999) == ([], 999, 2)


def test_wait_returns_immediately_when_already_true(clock: FakeClock, buffer: _StubBuffer) -> None:
	assert buffer._wait(lambda: True, timeout=5.0) is True  # type: ignore[attr-defined]
	assert clock.sleeps == []


def test_wait_gives_up_at_the_deadline_without_sleeping_for_real(
	clock: FakeClock, buffer: _StubBuffer
) -> None:
	assert buffer._wait(lambda: False, timeout=5.0) is False  # type: ignore[attr-defined]
	assert clock.monotonic() >= 5.0


def test_wait_evaluates_once_even_with_a_zero_timeout(buffer: _StubBuffer) -> None:
	calls: list[int] = []

	def _predicate() -> bool:
		calls.append(1)
		return True

	assert buffer._wait(_predicate, timeout=0.0) is True  # type: ignore[attr-defined]
	assert len(calls) == 1


def test_each_entry_carries_the_wall_clock_it_was_captured_at(clock: FakeClock) -> None:
	buffer = _StubBuffer(clock)
	clock.advance(10)
	buffer.append("one")
	clock.advance(5)
	buffer.append("two")
	entries, _from_index, _to_index = buffer.entries_since(1)
	assert [at for _text, _index, _pos, at in entries] == [10.0, 15.0]


def test_time_at_reads_one_entrys_stamp_by_index(clock: FakeClock) -> None:
	buffer = _StubBuffer(clock)
	clock.advance(7)
	buffer.append("one")
	assert buffer.time_at(1) == 7.0


def test_the_sentinel_has_no_stamp(clock: FakeClock) -> None:
	# Index 0 was never captured, so it claims no instant.
	assert _StubBuffer(clock).time_at(0) == 0.0


def test_a_stale_bookmark_reads_zero_rather_than_raising(clock: FakeClock) -> None:
	buffer = _StubBuffer(clock)
	buffer.append("one")
	assert buffer.time_at(99) == 0.0
	assert buffer.time_at(-1) == 0.0


def test_the_two_clocks_stay_separate(clock: FakeClock) -> None:
	# The stamp comes from time() and the still-speaking heuristic from monotonic(); the fake shares one
	# counter, so this checks that appending advances both.
	buffer = _StubBuffer(clock)
	clock.advance(3)
	buffer.append("one")
	assert buffer.time_at(1) == 3.0
	assert buffer.heuristic_mark() == 3.0
