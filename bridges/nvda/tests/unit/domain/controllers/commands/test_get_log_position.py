# Unit tests for domain/controllers/commands/get_log_position.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# Spec 0021's programmatic F1 ritual: mark the moment observation starts, so
# "everything since then" is answerable later without a span that was never
# built. The command must be cheap and must not disturb the span timeline.

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
	# The whole reason it is a separate command: paying for a slice to learn one
	# integer defeats the purpose of marking the moment you start observing.
	capture = FakeLogCapture()
	ctx = make_context(clock, log_capture=capture)
	capture.feed("a record that must not be fetched")

	_position(ctx)

	assert capture.slice_calls == []


def test_the_wall_clock_is_the_transcripts_own_format(clock: FakeClock) -> None:
	# Lining a mark up against the transcript, the journal's `created` stamps and
	# the human's "around then" should not need a format negotiation, so this is
	# the transcript's shape (with the date, unlike NVDA's time-only log lines).
	stamp = _position(make_context(FakeClock(start=1_770_000_000.0))).time

	parsed = datetime.strptime(stamp, "%Y-%m-%d %H:%M:%S.%f")
	assert parsed.year >= 2026


def test_the_wall_clock_comes_from_the_clock_port(clock: FakeClock) -> None:
	# Not datetime.now() reached for directly: the field has to be fakeable, or
	# nothing about it is testable at all.
	early = _position(make_context(FakeClock(start=1_770_000_000.0))).time
	later = _position(make_context(FakeClock(start=1_770_000_000.0 + 3600))).time

	assert later > early


def test_it_does_not_mark_a_span_of_its_own() -> None:
	# It IS the mark. A span for it would, by construction, hold no records -- and
	# would silently become getLog's default anchor.
	assert GetLogPositionHandler.marks_log is False
