# Unit tests for domain/controllers/commands/get_log_position.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from datetime import datetime

from fakes.clock import FakeClock
from fakes.log_capture import FakeLogCapture
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.get_log_position import GetLogPositionHandler
from nvdaMcpBridge.domain.controllers.commands.session_context import SessionContext
from support.context import make_context, request


def _position(ctx: SessionContext) -> p.LogPositionResult:
	result = GetLogPositionHandler().execute(ctx, request("getLogPosition"))
	assert isinstance(result, p.LogPositionResult)
	return result


def test_reports_the_journals_current_position(clock: FakeClock) -> None:
	capture = FakeLogCapture()
	ctx = make_context(clock, log_capture=capture)
	capture.feed("one")
	capture.feed("two")

	assert _position(ctx).position == 2


def test_an_untouched_journal_marks_at_zero(clock: FakeClock) -> None:
	assert _position(make_context(clock, log_capture=FakeLogCapture())).position == 0


def test_the_mark_moves_with_the_journal(clock: FakeClock) -> None:
	capture = FakeLogCapture()
	ctx = make_context(clock, log_capture=capture)

	first = _position(ctx).position
	capture.feed("something happened")
	second = _position(ctx).position

	assert second == first + 1


def test_it_reads_no_records_at_all(clock: FakeClock) -> None:
	capture = FakeLogCapture()
	ctx = make_context(clock, log_capture=capture)
	capture.feed("a record that must not be fetched")

	_position(ctx)

	assert capture.slice_calls == []


def test_the_wall_clock_is_the_transcripts_own_format(clock: FakeClock) -> None:
	stamp = _position(make_context(FakeClock(start=1_770_000_000.0))).time

	parsed = datetime.strptime(stamp, "%Y-%m-%d %H:%M:%S.%f")
	assert parsed.year >= 2026


def test_the_wall_clock_comes_from_the_clock_port(clock: FakeClock) -> None:
	early = _position(make_context(FakeClock(start=1_770_000_000.0))).time
	later = _position(make_context(FakeClock(start=1_770_000_000.0 + 3600))).time

	assert later > early


def test_it_does_not_mark_a_span_of_its_own() -> None:
	# A span for the mark would hold no records and would become getLog's default anchor.
	assert GetLogPositionHandler.marks_log is False
