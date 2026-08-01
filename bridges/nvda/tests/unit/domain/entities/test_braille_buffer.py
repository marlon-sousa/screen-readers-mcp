# Unit tests for domain/entities/braille_buffer.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# Only what BrailleBuffer adds on top of IndexedBuffer: recording genuine
# changes rather than refreshes. The base's index bookkeeping is tested in
# test_indexed_buffer.py.

from __future__ import annotations

import pytest
from fakes.clock import FakeClock
from nvdaMcpBridge.domain.entities.braille_buffer import BrailleBuffer


@pytest.fixture
def braille(clock: FakeClock) -> BrailleBuffer:
	return BrailleBuffer(clock)


def test_consecutive_duplicates_are_dropped(braille: BrailleBuffer) -> None:
	# NVDA rewrites the whole window on every update; a refresh is not a change.
	braille.append("line one")
	braille.append("line one")
	assert braille.next_index() == 2


def test_empty_and_whitespace_only_updates_are_ignored(braille: BrailleBuffer) -> None:
	braille.append("")
	braille.append("   ")
	assert braille.next_index() == 1  # nothing recorded


def test_text_is_trimmed(braille: BrailleBuffer) -> None:
	braille.append("  padded  ")
	assert braille.get_last() == ("padded", 1)


def test_a_repeat_after_a_change_is_recorded(braille: BrailleBuffer) -> None:
	# Only *consecutive* duplicates collapse; returning to earlier text is a
	# genuine change.
	braille.append("one")
	braille.append("two")
	braille.append("one")
	entries, _from_index, _to_index = braille.entries_since(1)
	assert [e[0] for e in entries] == ["one", "two", "one"]


def test_changes_read_back_in_order(braille: BrailleBuffer) -> None:
	braille.append("line one")
	braille.append("line one")  # duplicate refresh -> dropped
	braille.append("   ")  # whitespace only -> dropped
	braille.append("line two")
	entries, from_index, to_index = braille.entries_since(1)
	assert [e[0] for e in entries] == ["line one", "line two"]
	assert (from_index, to_index) == (1, 3)


def test_a_dropped_refresh_takes_its_log_position_with_it(braille: BrailleBuffer) -> None:
	# The positions list must stay in step with the entries list: a duplicate that
	# is not recorded must not record a position either, or every later entry
	# reports the position of the one before it.
	braille.append("line one", 5)
	braille.append("line one", 6)  # duplicate refresh -> dropped, position and all
	braille.append("line two", 7)
	entries, _from_index, _to_index = braille.entries_since(1)
	assert [(e[0], e[2]) for e in entries] == [("line one", 5), ("line two", 7)]
