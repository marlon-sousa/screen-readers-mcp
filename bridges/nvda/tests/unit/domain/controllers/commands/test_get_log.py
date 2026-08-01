# Unit tests for domain/controllers/commands/get_log.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# Spec 0020's test plan, item 12: the default anchor, windows > 1, an unknown id,
# and that getLog never becomes its own anchor. Spec 0021's item 10: each of the
# three anchors, and that supplying two of them is refused. The handler is driven
# with a hand-built SessionContext whose command_windows are seeded directly --
# the Session's own bracketing is tested in test_session.py, so these tests are
# about what the handler does with windows once they exist.
#
# A seeded window carries no end (spec 0021): a span runs to the NEXT window's
# start, or to the journal's current position for the last, still-open one. So
# these tests feed the journal and mark a window in the same interleaved order a
# real session would, and the spans fall out of that.

from __future__ import annotations

from typing import Any

import pytest
from fakes.clock import FakeClock
from fakes.log_capture import FakeLogCapture
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.command_handler import CommandError
from nvdaMcpBridge.domain.controllers.commands.get_log import GetLogHandler
from nvdaMcpBridge.domain.controllers.commands.session_context import SessionContext
from support.context import make_context, request


def _context(clock: FakeClock, capture: FakeLogCapture) -> SessionContext:
	return make_context(clock, log_capture=capture)


def _window(
	ctx: SessionContext,
	command_id: int,
	start: int,
	level: p.LogLevel = p.LogLevel.INFO,
) -> None:
	"""Mark a command window opening at *start* -- no end; spec 0021 computes it."""
	ctx.command_windows.append((command_id, start, level))


def _get_log(ctx: SessionContext, **params: Any) -> p.LogSliceResult:
	result = GetLogHandler().execute(ctx, request("getLog", **params))
	assert isinstance(result, p.LogSliceResult)
	return result


# -- anchoring ----------------------------------------------------------------


def test_get_log_does_not_mark_its_own_window() -> None:
	# The whole reason for the flag: otherwise the default anchor is always the
	# getLog that just ran, whose window is empty by construction.
	assert GetLogHandler.marks_log is False


def test_default_anchor_is_the_most_recent_window(clock: FakeClock) -> None:
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	capture.feed("first command")
	_window(ctx, 7, 0)
	capture.feed("second command")
	_window(ctx, 8, 1)

	result = _get_log(ctx)

	assert result.fromCommandId == 8
	assert result.toCommandId == 8
	assert "second command" in result.text
	assert "first command" not in result.text


def test_explicit_command_id_anchors_on_that_window(clock: FakeClock) -> None:
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	capture.feed("for seven")
	_window(ctx, 7, 0)
	capture.feed("for eight")
	_window(ctx, 8, 1)

	result = _get_log(ctx, commandId=7)

	assert result.fromCommandId == 7
	assert "for seven" in result.text
	assert "for eight" not in result.text


def test_unknown_command_id_is_a_command_error(clock: FakeClock) -> None:
	ctx = _context(clock, FakeLogCapture())
	_window(ctx, 7, 0)

	with pytest.raises(CommandError, match="99 not found"):
		_get_log(ctx, commandId=99)


def test_no_windows_at_all_is_a_command_error(clock: FakeClock) -> None:
	ctx = _context(clock, FakeLogCapture())

	with pytest.raises(CommandError, match="no commands have been marked"):
		_get_log(ctx)


# -- the position and time anchors (spec 0021) ---------------------------------


def test_since_position_reads_forward_from_the_cursor(clock: FakeClock) -> None:
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	capture.feed("before the mark")
	cursor = capture.position()
	capture.feed("after the mark")

	result = _get_log(ctx, sincePosition=cursor)

	assert "after the mark" in result.text
	assert "before the mark" not in result.text
	assert result.entries == 1


def test_since_position_needs_no_command_windows_at_all(clock: FakeClock) -> None:
	# The point of the cursor anchor: an agent watching a HUMAN drive the reader
	# issues no marking commands, so the default anchor has nothing to anchor on.
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	capture.feed("the human pressed something")

	result = _get_log(ctx, sincePosition=0)

	assert ctx.command_windows == []
	assert result.entries == 1
	assert result.fromCommandId is None
	assert result.toCommandId is None


def test_reading_a_position_twice_returns_the_same_records(clock: FakeClock) -> None:
	# Nothing is consumed: the caller holds the cursor, so re-issuing it -- to
	# re-filter, say -- is idempotent rather than empty.
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	capture.feed("once")

	first = _get_log(ctx, sincePosition=0)
	second = _get_log(ctx, sincePosition=0)

	assert first.text == second.text
	assert first.entries == second.entries == 1


def test_next_position_continues_the_tail_without_gap_or_repeat(clock: FakeClock) -> None:
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	capture.feed("one")

	first = _get_log(ctx, sincePosition=0)
	capture.feed("two")
	second = _get_log(ctx, sincePosition=first.nextPosition)

	assert "one" in first.text and "two" not in first.text
	assert "two" in second.text and "one" not in second.text
	assert second.nextPosition > first.nextPosition


def test_last_seconds_reads_back_from_now(clock: FakeClock) -> None:
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	capture.feed("a minute ago", created=1000.0)
	capture.feed("just now", created=1055.0)
	capture.now = 1060.0

	result = _get_log(ctx, lastSeconds=10.0)

	assert "just now" in result.text
	assert "a minute ago" not in result.text
	assert result.fromCommandId is None


def test_two_anchors_at_once_is_refused(clock: FakeClock) -> None:
	# A precedence puzzle would be worse than an error: the two anchors mean
	# genuinely different windows, and silently picking one hides the mistake.
	ctx = _context(clock, FakeLogCapture())

	with pytest.raises(CommandError, match="mutually exclusive"):
		_get_log(ctx, sincePosition=0, lastSeconds=5.0)


def test_a_position_anchor_and_a_command_id_at_once_is_refused(clock: FakeClock) -> None:
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	_window(ctx, 7, 0)

	with pytest.raises(CommandError, match="mutually exclusive"):
		_get_log(ctx, sincePosition=0, commandId=7)


def test_windows_alongside_a_position_anchor_is_refused(clock: FakeClock) -> None:
	# `windows` belongs to the command anchor and means nothing to the other two,
	# so accepting it there would answer a different question from the one asked:
	# the agent sent windows: 3 and would be handed a position tail with no way to
	# tell. Refused for the reason an unknown field name is -- a plausible-looking
	# wrong answer is worse than an error.
	ctx = _context(clock, FakeLogCapture())

	with pytest.raises(CommandError, match="windows applies to the commandId anchor"):
		_get_log(ctx, sincePosition=0, windows=3)


def test_the_default_windows_does_not_make_a_position_anchor_an_error(clock: FakeClock) -> None:
	# windows defaults to 1, so it is always "present"; only a value the agent
	# cannot have defaulted into may be treated as a mistake.
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	capture.feed("something")

	assert _get_log(ctx, sincePosition=0).entries == 1


def test_a_position_anchor_reports_the_level_in_force_now(clock: FakeClock) -> None:
	# Approximate by construction (spec 0021): a position range may straddle a
	# setLogLevel, so this reports what is in force rather than claiming exactness.
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	capture.start(p.LogLevel.DEBUG)
	capture.feed("something")

	assert _get_log(ctx, sincePosition=0).capturedAtLevel is p.LogLevel.DEBUG


# -- windows > 1 ---------------------------------------------------------------


def test_windows_counts_back_from_the_anchor(clock: FakeClock) -> None:
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	for index, command_id in enumerate((5, 6, 7)):
		capture.feed(f"command {command_id}")
		_window(ctx, command_id, index)

	result = _get_log(ctx, windows=3)

	assert result.fromCommandId == 5
	assert result.toCommandId == 7
	assert result.entries == 3
	for command_id in (5, 6, 7):
		assert f"command {command_id}" in result.text


def test_windows_are_returned_in_order(clock: FakeClock) -> None:
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	for index, command_id in enumerate((5, 6, 7)):
		capture.feed(f"command {command_id}")
		_window(ctx, command_id, index)

	text = _get_log(ctx, windows=3).text

	assert text.index("command 5") < text.index("command 6") < text.index("command 7")


def test_windows_beyond_what_exists_returns_what_there_is(clock: FakeClock) -> None:
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	capture.feed("only one")
	_window(ctx, 7, 0)

	result = _get_log(ctx, windows=50)

	assert result.fromCommandId == 7
	assert result.entries == 1


def test_a_multi_window_range_is_one_contiguous_span(clock: FakeClock) -> None:
	# Spans are adjacent under 0021, so a multi-window range is simply the first
	# window's start to the current position -- there is no gap left to include or
	# exclude, and slicing each window separately would give the same interval.
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	capture.feed("inside command 5")
	_window(ctx, 5, 0)
	capture.feed("what command 5 actually caused, a millisecond late")
	capture.feed("inside command 6")
	_window(ctx, 6, 2)

	result = _get_log(ctx, windows=2)

	assert "inside command 5" in result.text
	assert "inside command 6" in result.text
	assert "a millisecond late" in result.text
	assert result.entries == 3


def test_a_single_span_holds_the_work_its_command_caused(clock: FakeClock) -> None:
	# The case 0021 exists for, and the one 11.4's model failed. A window used to
	# close when the handler returned, but NVDA does the work the command CAUSED
	# just after that, on its own thread: live, `speech.speech.speak` landed one
	# millisecond past a gesture window's end mark and fell into the gap. Under
	# the span model there is no gap -- command 5's span runs until command 6 is
	# dispatched, so the record it caused is attributed to it with windows=1.
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	capture.feed("before")
	_window(ctx, 5, 1)
	capture.feed("inside command 5")
	capture.feed("what command 5 caused, a millisecond late")
	_window(ctx, 6, 3)
	capture.feed("inside command 6")

	result = _get_log(ctx, commandId=5)

	assert "inside command 5" in result.text
	assert "a millisecond late" in result.text
	assert "before" not in result.text
	assert "inside command 6" not in result.text
	assert result.entries == 2


# -- filters reach the journal -------------------------------------------------


def test_filters_are_passed_through_to_the_journal(clock: FakeClock) -> None:
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	capture.feed_record(12, "IO", "speech.speech.speak", "Speaking hello")
	capture.feed_record(20, "INFO", "core", "focus changed")
	_window(ctx, 7, 0)

	result = _get_log(ctx, commandId=7, minLevel="info")

	assert "focus changed" in result.text
	assert "Speaking hello" not in result.text
	assert result.entries == 1
	assert capture.slice_calls[0].min_level is p.LogLevel.INFO


def test_exclude_matches_the_module_name(clock: FakeClock) -> None:
	# The spec's own worked example: at debug, drop speech and keep the rest. It
	# only works if the journal's "module" really is NVDA's codepath.
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	capture.feed_record(12, "IO", "speech.speech.speak", "Speaking [Elements list]")
	capture.feed_record(10, "DEBUG", "IAccessibleHandler", "COMError")
	_window(ctx, 7, 0)

	result = _get_log(ctx, commandId=7, exclude=["speech.speech.speak"])

	assert "COMError" in result.text
	assert "Elements list" not in result.text


def test_unknown_field_is_a_command_error_not_a_silent_omission(clock: FakeClock) -> None:
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	capture.feed("something")
	_window(ctx, 7, 0)

	with pytest.raises(CommandError, match="unknown log field"):
		_get_log(ctx, commandId=7, fields=["levl", "message"])


# -- bounds --------------------------------------------------------------------


def test_max_entries_caps_across_all_windows(clock: FakeClock) -> None:
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	for index, command_id in enumerate((5, 6, 7)):
		capture.feed(f"command {command_id}")
		_window(ctx, command_id, index)

	result = _get_log(ctx, windows=3, maxEntries=2)

	# The cap is the TOTAL, not per window, and matched still counts everything
	# that passed the filters so the agent knows how much it is not seeing.
	assert result.entries == 2
	assert result.matched == 3
	assert result.truncated


def test_truncation_in_any_window_is_reported(clock: FakeClock) -> None:
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	capture.feed("one")
	capture.feed("two")
	_window(ctx, 5, 0)
	capture.feed("three")
	_window(ctx, 6, 2)

	result = _get_log(ctx, windows=2, maxEntries=1)

	assert result.truncated
	assert result.matched == 3
	assert result.entries == 1


# -- capturedAtLevel -----------------------------------------------------------


def test_an_empty_slice_still_reports_the_floor_it_was_captured_at(
	clock: FakeClock,
) -> None:
	# The ambiguity the field exists to kill: an empty answer to `minLevel: debug`
	# means either "nothing happened" or "you were not capturing that deep". A
	# window recorded at info emitted no DEBUG records at all, so no filter can
	# recover them -- and capturedAtLevel is how the agent learns to call
	# set_log_level and re-run rather than retrying the same query.
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	_window(ctx, 7, 0, level=p.LogLevel.INFO)

	result = _get_log(ctx, commandId=7, minLevel="debug")

	assert result.entries == 0
	assert result.matched == 0
	assert result.capturedAtLevel is p.LogLevel.INFO


def test_min_level_is_a_floor_so_coarser_records_still_pass(clock: FakeClock) -> None:
	# minLevel: "debug" means "debug AND ABOVE", so an INFO record is kept. Only
	# the levels BELOW the threshold drop -- NVDA logs speech at IO (12), which is
	# how the spec's `minLevel: "info"` case removes speech.
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	capture.feed_record(12, "IO", "speech.speech.speak", "Speaking hello")
	capture.feed_record(20, "INFO", "core", "focus changed")
	_window(ctx, 7, 0)

	kept_at_debug = _get_log(ctx, commandId=7, minLevel="debug")
	kept_at_info = _get_log(ctx, commandId=7, minLevel="info")

	assert kept_at_debug.entries == 2  # IO (12) and INFO (20) are both >= 10
	assert kept_at_info.entries == 1
	assert "Speaking hello" not in kept_at_info.text


def test_captured_at_level_of_a_multi_window_range_is_the_oldest(
	clock: FakeClock,
) -> None:
	capture = FakeLogCapture()
	ctx = _context(clock, capture)
	capture.feed("early")
	_window(ctx, 5, 0, level=p.LogLevel.INFO)
	capture.feed("late")
	_window(ctx, 6, 1, level=p.LogLevel.DEBUG)

	# The conservative end of the range: never claims to have captured more than
	# it did for the earliest window in the answer.
	assert _get_log(ctx, windows=2).capturedAtLevel is p.LogLevel.INFO
