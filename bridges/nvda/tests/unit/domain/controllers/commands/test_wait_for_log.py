# Unit tests for domain/controllers/commands/wait_for_log.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# Spec 0021's item 11: a match, a timeout, and the manners waitForSpeech
# established -- a `found: false` answer rather than an error when nothing
# matched, and a position that is usable either way. The "a long wait does not
# trip the watchdogs" half lives in test_session.py, because only the Session
# owns the deadlines it must not trip.
#
# Every match here has to ARRIVE DURING the wait, because that is the only kind
# the command answers: it starts from the journal's position at dispatch, so an
# error from five minutes ago can never satisfy "wait for the next error". The
# capture below therefore logs on a chosen poll, and the fake clock makes each
# poll instant -- a thirty-second timeout costs microseconds.

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
	assert clock.sleeps == []  # it was already there; nothing to wait for


def test_a_record_that_arrives_later_in_the_wait_is_matched(clock: FakeClock) -> None:
	capture = ArrivesOnPoll(_logs((*ERROR, "COMError from IAccessible")), after=3)
	ctx = make_context(clock, log_capture=capture)

	result = _wait(ctx, timeout=30.0, minLevel="error")

	assert result.found is True
	assert "COMError" in result.text
	assert capture.polls == 4, "the handler should have polled until the record landed"


def test_it_only_matches_records_logged_after_the_wait_began(clock: FakeClock) -> None:
	# Otherwise "wait for the next error" would return instantly with an error from
	# five minutes ago, and a poll loop could never advance.
	capture = ArrivesOnPoll(_logs((*ERROR, "the new error")), after=2)
	capture.feed_record(40, "ERROR", "core", "an error from before the wait")
	ctx = make_context(clock, log_capture=capture)

	result = _wait(ctx, timeout=30.0, minLevel="error")

	assert result.found is True
	assert "the new error" in result.text
	assert "before the wait" not in result.text


def test_nothing_matching_is_a_miss_not_an_error(clock: FakeClock) -> None:
	# waitForSpeech's manners: a wait that expires is an answer, not a fault --
	# "nothing went wrong in those thirty seconds" is exactly what an agent asked.
	capture = ArrivesOnPoll(_logs((*INFO, "all quiet")))
	ctx = make_context(clock, log_capture=capture)

	result = _wait(ctx, timeout=5.0, minLevel="error")

	assert result.found is False
	assert result.text == ""


def test_a_miss_still_returns_a_usable_position(clock: FakeClock) -> None:
	# So a caller can carry straight on with sincePosition rather than having to
	# take a fresh mark after every unsuccessful wait.
	capture = ArrivesOnPoll(_logs((*INFO, "all quiet")))
	ctx = make_context(clock, log_capture=capture)

	result = _wait(ctx, timeout=5.0, minLevel="error")

	assert result.position == capture.position()


def test_the_match_position_is_one_past_the_record(clock: FakeClock) -> None:
	# The mark() convention: it feeds straight back in as the next sincePosition
	# and reads what came AFTER the trigger, without repeating the trigger itself.
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
	# Clamped in the BRIDGE, not only in the server's tool schema, so it protects
	# every client. The command-inactivity watchdog is measured from dispatch and
	# is not refreshed when a handler returns (spec 0016), so a wait allowed to
	# outlast it would answer the agent and have the session torn down under it.
	ctx = make_context(clock, log_capture=FakeLogCapture())

	_wait(ctx, timeout=600.0, minLevel="error")

	assert clock.monotonic() <= MAX_POLL_TIMEOUT + 1.0, (
		f"the wait ran for {clock.monotonic()}s, past the {MAX_POLL_TIMEOUT}s cap"
	)


def test_a_clamped_timeout_is_said_out_loud_in_the_transcript(clock: FakeClock) -> None:
	# Silently waiting less than asked would look like a fast, wrong answer.
	transcript = FakeTranscript()
	ctx = make_context(clock, log_capture=FakeLogCapture(), transcript=transcript)

	_wait(ctx, timeout=600.0, minLevel="error")

	assert any("clamped" in str(event) for event in transcript.events)


def test_a_teardown_request_ends_the_wait_at_once(clock: FakeClock) -> None:
	# The panic path. Teardown is cooperative -- the loop honours it at its next
	# wakeup -- and a handler blocked for its whole timeout does not reach that
	# wakeup. Meanwhile the requester is NVDA's MAIN THREAD, joined on this one,
	# so a wait that ignored the request would freeze the reader for the rest of
	# its timeout: the exact opposite of what pressing panic is for.
	torn_down = False

	def teardown_requested() -> bool:
		return torn_down

	ctx = make_context(clock, log_capture=FakeLogCapture(), teardown_requested=teardown_requested)
	torn_down = True

	result = _wait(ctx, timeout=110.0, minLevel="error")

	# A miss, not an error: the session is ending, and the caller gets the
	# ordinary answer rather than a fault to interpret.
	assert result.found is False
	assert clock.monotonic() < 110.0, f"the wait ran {clock.monotonic()}s after teardown was requested"


def test_a_wait_runs_normally_while_no_teardown_is_pending(clock: FakeClock) -> None:
	# The guard must not make every wait return instantly.
	ctx = make_context(clock, log_capture=FakeLogCapture())

	_wait(ctx, timeout=5.0, minLevel="error")

	assert clock.monotonic() >= 5.0


def test_it_marks_a_span_like_any_other_command() -> None:
	# Unlike getLog and getLogPosition, this one DOES work: the wait is the thing
	# the agent asked for, so the records that arrived during it belong to it.
	assert WaitForLogHandler.marks_log is True
