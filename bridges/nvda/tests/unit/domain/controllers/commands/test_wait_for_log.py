# Unit tests for domain/controllers/commands/wait_for_log.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# The command starts from the journal's position at dispatch, so every match here arrives during the wait.

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from fakes.clock import FakeClock
from fakes.log_capture import FakeLogCapture
from fakes.transcript import FakeTranscript
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.command_handler import MAX_POLL_TIMEOUT
from nvdaMcpBridge.domain.controllers.commands.session_context import SessionContext
from nvdaMcpBridge.domain.controllers.commands.wait_for_log import WaitForLogHandler
from support.context import make_context, request


class ArrivesOnPoll(FakeLogCapture):
	"""A capture that runs *arrive* once the handler has polled *after* times."""

	def __init__(self, arrive: Callable[[FakeLogCapture], None], *, after: int = 0) -> None:
		super().__init__()
		self._arrive = arrive
		self._after = after
		self.polls = 0

	def find_since(
		self,
		start: int,
		*,
		min_level: p.LogLevel | None = None,
		contains: list[str] | None = None,
	) -> tuple[int, str] | None:
		if self.polls == self._after:
			self._arrive(self)
		self.polls += 1
		return super().find_since(start, min_level=min_level, contains=contains)


def _logs(*records: tuple[int, str, str]) -> Callable[[FakeLogCapture], None]:
	"""An arrival that writes *records* as (level_no, level_name, message)."""

	def arrive(capture: FakeLogCapture) -> None:
		for level_no, level_name, message in records:
			capture.feed_record(level_no, level_name, "core", message)

	return arrive


ERROR = (40, "ERROR")
INFO = (20, "INFO")


def _wait(ctx: SessionContext, **params: Any) -> p.WaitForLogResult:
	result = WaitForLogHandler().execute(ctx, request("waitForLog", **params))
	assert isinstance(result, p.WaitForLogResult)
	return result


def test_a_record_on_the_first_poll_is_matched_without_waiting(clock: FakeClock) -> None:
	capture = ArrivesOnPoll(_logs((*ERROR, "COMError from IAccessible")))
	ctx = make_context(clock, log_capture=capture)

	result = _wait(ctx, timeout=30.0, minLevel="error")

	assert result.found is True
	assert "COMError" in result.text
	assert clock.sleeps == []


def test_a_record_that_arrives_later_in_the_wait_is_matched(clock: FakeClock) -> None:
	capture = ArrivesOnPoll(_logs((*ERROR, "COMError from IAccessible")), after=3)
	ctx = make_context(clock, log_capture=capture)

	result = _wait(ctx, timeout=30.0, minLevel="error")

	assert result.found is True
	assert "COMError" in result.text
	assert capture.polls == 4, "the handler should have polled until the record landed"


def test_it_only_matches_records_logged_after_the_wait_began(clock: FakeClock) -> None:
	capture = ArrivesOnPoll(_logs((*ERROR, "the new error")), after=2)
	capture.feed_record(40, "ERROR", "core", "an error from before the wait")
	ctx = make_context(clock, log_capture=capture)

	result = _wait(ctx, timeout=30.0, minLevel="error")

	assert result.found is True
	assert "the new error" in result.text
	assert "before the wait" not in result.text


def test_nothing_matching_is_a_miss_not_an_error(clock: FakeClock) -> None:
	capture = ArrivesOnPoll(_logs((*INFO, "all quiet")))
	ctx = make_context(clock, log_capture=capture)

	result = _wait(ctx, timeout=5.0, minLevel="error")

	assert result.found is False
	assert result.text == ""


def test_a_miss_still_returns_a_usable_position(clock: FakeClock) -> None:
	capture = ArrivesOnPoll(_logs((*INFO, "all quiet")))
	ctx = make_context(clock, log_capture=capture)

	result = _wait(ctx, timeout=5.0, minLevel="error")

	assert result.position == capture.position()


def test_the_match_position_is_one_past_the_record(clock: FakeClock) -> None:
	capture = ArrivesOnPoll(_logs((*ERROR, "the error"), (*INFO, "the aftermath")))
	ctx = make_context(clock, log_capture=capture)

	result = _wait(ctx, timeout=5.0, minLevel="error")

	assert result.position == 1
	text, entries, _matched, _truncated = capture.slice_since(result.position)
	assert entries == 1
	assert "the aftermath" in text


def test_it_waits_the_whole_timeout_before_giving_up(clock: FakeClock) -> None:
	ctx = make_context(clock, log_capture=FakeLogCapture())

	_wait(ctx, timeout=5.0, minLevel="error")

	assert clock.monotonic() >= 5.0


def test_a_zero_timeout_still_checks_once(clock: FakeClock) -> None:
	capture = ArrivesOnPoll(_logs((*ERROR, "already there")))
	ctx = make_context(clock, log_capture=capture)

	assert _wait(ctx, timeout=0.0, minLevel="error").found is True


def test_contains_matches_without_a_level(clock: FakeClock) -> None:
	capture = ArrivesOnPoll(_logs((*INFO, "Elements list dialog")))
	ctx = make_context(clock, log_capture=capture)

	assert _wait(ctx, timeout=1.0, contains=["elements list"]).found is True


def test_a_timeout_beyond_the_inactivity_window_is_clamped(clock: FakeClock) -> None:
	# The inactivity watchdog is measured from dispatch and not refreshed when a handler returns, so a
	# longer wait would have the session torn down under it.
	ctx = make_context(clock, log_capture=FakeLogCapture())

	_wait(ctx, timeout=600.0, minLevel="error")

	assert clock.monotonic() <= MAX_POLL_TIMEOUT + 1.0, (
		f"the wait ran for {clock.monotonic()}s, past the {MAX_POLL_TIMEOUT}s cap"
	)


def test_a_clamped_timeout_is_said_out_loud_in_the_transcript(clock: FakeClock) -> None:
	transcript = FakeTranscript()
	ctx = make_context(clock, log_capture=FakeLogCapture(), transcript=transcript)

	_wait(ctx, timeout=600.0, minLevel="error")

	assert any("clamped" in str(event) for event in transcript.events)


def test_a_teardown_request_ends_the_wait_at_once(clock: FakeClock) -> None:
	# The teardown requester is NVDA's main thread, joined on this one; ignoring it freezes the reader.
	torn_down = False

	def teardown_requested() -> bool:
		return torn_down

	ctx = make_context(clock, log_capture=FakeLogCapture(), teardown_requested=teardown_requested)
	torn_down = True

	result = _wait(ctx, timeout=110.0, minLevel="error")

	assert result.found is False
	assert clock.monotonic() < 110.0, f"the wait ran {clock.monotonic()}s after teardown was requested"


def test_a_wait_runs_normally_while_no_teardown_is_pending(clock: FakeClock) -> None:
	ctx = make_context(clock, log_capture=FakeLogCapture())

	_wait(ctx, timeout=5.0, minLevel="error")

	assert clock.monotonic() >= 5.0


def test_it_marks_a_span_like_any_other_command() -> None:
	assert WaitForLogHandler.marks_log is True
