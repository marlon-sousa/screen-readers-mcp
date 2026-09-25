# Unit tests for domain/entities/document_snapshot.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.entities.document_snapshot import DocumentSnapshot


def _fill(snapshot: DocumentSnapshot, lines: list[str]) -> int:
	"""Offer *lines* the way a reader does; return how many were offered."""
	offered = 0
	for line in lines:
		offered += 1
		if not snapshot.offer(line):
			break
	return offered


def test_unbounded_takes_the_whole_document() -> None:
	snapshot = DocumentSnapshot()
	_fill(snapshot, ["one", "two", "three"])
	assert [line.text for line in snapshot.lines] == ["one", "two", "three"]
	assert snapshot.truncated_by is p.TruncatedBy.NONE
	assert (snapshot.from_line, snapshot.to_line) == (0, 3)


def test_max_lines_bites_and_says_so() -> None:
	snapshot = DocumentSnapshot(max_lines=2)
	offered = _fill(snapshot, ["one", "two", "three", "four"])
	assert [line.text for line in snapshot.lines] == ["one", "two"]
	assert snapshot.truncated_by is p.TruncatedBy.MAX_LINES
	# The walk stops at the bound, because rendering is the expensive half.
	assert offered == 3


def test_max_chars_bites_and_says_so() -> None:
	snapshot = DocumentSnapshot(max_chars=7)
	_fill(snapshot, ["1234", "5678", "9"])
	assert [line.text for line in snapshot.lines] == ["1234"]
	assert snapshot.truncated_by is p.TruncatedBy.MAX_CHARS


def test_a_document_ending_exactly_on_a_bound_is_not_truncated() -> None:
	snapshot = DocumentSnapshot(max_lines=3)
	_fill(snapshot, ["one", "two", "three"])
	assert len(snapshot.lines) == 3
	assert snapshot.truncated_by is p.TruncatedBy.NONE


def test_the_first_line_is_taken_however_small_the_char_budget() -> None:
	snapshot = DocumentSnapshot(max_chars=1)
	_fill(snapshot, ["a very long first line", "second"])
	assert [line.text for line in snapshot.lines] == ["a very long first line"]
	assert snapshot.truncated_by is p.TruncatedBy.MAX_CHARS


def test_from_line_skips_but_ordinals_stay_absolute() -> None:
	snapshot = DocumentSnapshot(from_line=2)
	_fill(snapshot, ["zero", "one", "two", "three"])
	assert [(line.line, line.text) for line in snapshot.lines] == [(2, "two"), (3, "three")]
	assert (snapshot.from_line, snapshot.to_line) == (2, 4)


def test_from_line_past_the_end_is_an_empty_span_not_a_cap() -> None:
	snapshot = DocumentSnapshot(from_line=9)
	_fill(snapshot, ["zero", "one"])
	assert snapshot.lines == []
	assert (snapshot.from_line, snapshot.to_line) == (9, 9)
	assert snapshot.truncated_by is p.TruncatedBy.NONE


def test_bounds_combine_and_the_one_that_bit_is_the_one_reported() -> None:
	snapshot = DocumentSnapshot(from_line=1, max_lines=2, max_chars=1000)
	_fill(snapshot, ["zero", "one", "two", "three", "four"])
	assert [line.line for line in snapshot.lines] == [1, 2]
	assert snapshot.truncated_by is p.TruncatedBy.MAX_LINES


def test_negative_bounds_are_clamped_rather_than_rejected() -> None:
	snapshot = DocumentSnapshot(from_line=-5, max_lines=-1, max_chars=-1)
	_fill(snapshot, ["one", "two"])
	assert [line.text for line in snapshot.lines] == ["one", "two"]
	assert snapshot.truncated_by is p.TruncatedBy.NONE


def test_an_empty_document_is_an_empty_span() -> None:
	snapshot = DocumentSnapshot()
	assert snapshot.lines == []
	assert (snapshot.from_line, snapshot.to_line) == (0, 0)
	assert snapshot.truncated_by is p.TruncatedBy.NONE
