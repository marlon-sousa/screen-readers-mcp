# Unit tests for adapters/nvda_silent_speech_source.py -- its THREE states.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# The mirror module for the silent speech source. Its sibling
# test_silent_mode_keeps_speech_callbacks_alive.py is a named regression scenario
# (board entry 11.13, the say-all stall) and keeps that name; this one covers the
# adapter's own contract, which spec 0032 widened from two states to three:
#
#   suppressing      filter registered, words emptied, buffer filled
#   suspended        filter unregistered (an askUser window)
#   passing through  filter registered, words UNTOUCHED, buffer filled
#
# The third state carries two traps that are invisible at every call site, and
# each has a test here because getting either wrong is silent:
#
#   * running the callbacks again while passing through would double-advance say
#     all -- re-inflicting 11.13's wound from the opposite direction;
#   * resume(), which ends an askUser window, must not re-mute a session the
#     silence cap has already lifted. That path is the RECOVERY path, so a bug in
#     it hands the harm back to the person the cap just rescued.

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import pytest
from fakes.clock import FakeClock
from support import nvda_stubs

nvda_stubs.install()

from nvdaMcpBridge.adapters.nvda_silent_speech_source import (
	CAP_LIFTED_MARKER,
	CAP_RESUPPRESSED_MARKER,
	RESTORED_MARKER,
	SUPPRESSED_MARKER,
	NvdaSilentSpeechSource,
)
from nvdaMcpBridge.domain.entities.speech_buffer import SpeechBuffer


@pytest.fixture(autouse=True)
def clean_extension_points() -> Iterator[None]:
	"""No registration outlives its test; NVDA's real points are process-wide."""
	yield
	nvda_stubs.reset()


class Started:
	"""A started source, its buffer, and the filter handler NVDA would call."""

	def __init__(self, clock: FakeClock) -> None:
		self.buffer = SpeechBuffer(clock, exact_finish=False)
		self.source = NvdaSilentSpeechSource()
		self.source.start(self.buffer, lambda: 0)

	@property
	def handler(self) -> Any:
		"""Whatever is registered right now -- None while suspended."""
		handlers = nvda_stubs.filter_speechSequence.handlers
		return handlers[0] if handlers else None

	def spoken(self) -> list[str]:
		"""Every line the buffer captured, in order."""
		return [entry[0] for entry in self.buffer.entries_since(1)[0]]


@pytest.fixture
def started(clock: FakeClock) -> Iterator[Started]:
	# NVDA holds filter handlers by WEAK reference, so the source has to outlive
	# the fixture body; the generator's own frame is what keeps it alive.
	state = Started(clock)
	yield state
	state.source.stop()


# -- the three states --------------------------------------------------------


def test_suppressing_captures_and_empties(started: Started) -> None:
	assert started.source.is_suppressing()
	assert started.handler(["a heading"]) == []
	assert started.spoken() == ["a heading"]


def test_passing_through_captures_and_hands_the_sequence_on(started: Started) -> None:
	started.source.stop_suppressing()

	sequence = ["a heading", "and more"]
	assert started.handler(sequence) == sequence, "the words did not reach the synth"
	assert started.spoken() == ["a heading and more"], "the agent lost evidence to give the human sound"
	assert not started.source.is_suppressing()


def test_suspending_withholds_nothing_and_captures_nothing(started: Started) -> None:
	started.source.suspend()
	assert started.handler is None, "the filter is still registered during a window"
	assert not started.source.is_suppressing()


def test_capture_survives_the_lift_with_its_indices_intact(started: Started) -> None:
	# The whole reason the lift is not `suspend`: the agent keeps its evidence.
	started.handler(["before"])
	started.source.stop_suppressing()
	started.handler(["after"])

	entries, from_index, to_index = started.buffer.entries_since(1)
	assert [(entry[0], entry[1]) for entry in entries] == [("before", 1), ("after", 2)]
	assert (from_index, to_index) == (1, 3), "the indices are not continuous across the transition"


# -- trap one: the callbacks -------------------------------------------------


def test_callbacks_are_advanced_while_suppressing(started: Started) -> None:
	ran: list[str] = []
	started.handler([nvda_stubs.StubCallbackCommand(lambda: ran.append("lineReached"))])
	nvda_stubs.eventQueue.pump()
	assert ran == ["lineReached"]


def test_callbacks_are_NOT_advanced_while_passing_through(started: Started) -> None:
	# The sequence reaches speech.speak() intact, so NVDA clocks the callback
	# itself. Running it here as well would advance say all twice per chunk.
	started.source.stop_suppressing()
	ran: list[str] = []
	command = nvda_stubs.StubCallbackCommand(lambda: ran.append("lineReached"))

	returned = started.handler([command, "a line"])
	nvda_stubs.eventQueue.pump()

	assert ran == [], "the callback was run a second time; say all would double-advance"
	assert command in returned, "the callback did not reach NVDA either -- say all stalls"
	assert nvda_stubs.eventQueue.queued == []


def test_re_suppressing_advances_callbacks_again(started: Started) -> None:
	started.source.stop_suppressing()
	started.source.resume_suppressing()
	ran: list[str] = []
	started.handler([nvda_stubs.StubCallbackCommand(lambda: ran.append("lineReached"))])
	nvda_stubs.eventQueue.pump()
	assert ran == ["lineReached"]


# -- trap two: resume() must not re-mute a lifted session --------------------


def test_resume_after_a_lift_restores_passing_through_not_suppression(started: Started) -> None:
	started.source.stop_suppressing()
	# An askUser window opens and closes across the lift, which is the ordinary
	# way this happens: waitForUserReply calls resume() on the answer.
	started.source.suspend()
	started.source.resume()

	assert started.handler is not None, "capture did not come back"
	assert not started.source.is_suppressing(), "the human was re-muted by the recovery path"
	assert started.handler(["still audible"]) == ["still audible"]


def test_resume_without_a_lift_still_re_suppresses(started: Started) -> None:
	started.source.suspend()
	started.source.resume()
	assert started.source.is_suppressing()
	assert started.handler(["muted again"]) == []


# -- idempotence -------------------------------------------------------------


def test_the_two_new_calls_are_idempotent(started: Started) -> None:
	started.source.stop_suppressing()
	started.source.stop_suppressing()
	assert not started.source.is_suppressing()
	started.source.resume_suppressing()
	started.source.resume_suppressing()
	assert started.source.is_suppressing()
	# One transition each, not two: a repeated call must not spam nvda.log.
	assert nvda_stubs.log.messages.count(CAP_LIFTED_MARKER) == 1
	assert nvda_stubs.log.messages.count(CAP_RESUPPRESSED_MARKER) == 1


# -- the log a human reads afterwards ----------------------------------------


def balanced(messages: list[str]) -> bool:
	"""Every 'suppressed' answered by a 'restored', in order and never doubled."""
	depth = 0
	for message in messages:
		if message == SUPPRESSED_MARKER:
			depth += 1
		elif message == RESTORED_MARKER:
			depth -= 1
		if depth not in (0, 1):
			return False
	return depth == 0


def test_a_lift_reports_both_what_and_why(started: Started) -> None:
	started.source.stop_suppressing()
	messages = nvda_stubs.log.messages
	assert messages == [SUPPRESSED_MARKER, CAP_LIFTED_MARKER, RESTORED_MARKER]


def test_the_markers_balance_across_a_lift_and_a_re_arm(clock: FakeClock) -> None:
	source = NvdaSilentSpeechSource()
	source.start(SpeechBuffer(clock, exact_finish=False), lambda: 0)
	source.stop_suppressing()
	source.resume_suppressing()
	source.stop()
	assert balanced(nvda_stubs.log.messages), (
		f"nvda.log claims a suppression that never ended: {nvda_stubs.log.messages}"
	)


def test_the_markers_balance_when_a_session_ends_while_lifted(clock: FakeClock) -> None:
	source = NvdaSilentSpeechSource()
	source.start(SpeechBuffer(clock, exact_finish=False), lambda: 0)
	source.stop_suppressing()
	source.stop()
	assert balanced(nvda_stubs.log.messages), (
		f"nvda.log claims a suppression that never ended: {nvda_stubs.log.messages}"
	)


def test_the_markers_balance_when_a_session_ends_with_a_window_open(clock: FakeClock) -> None:
	# The pre-existing case the _marked flag exists for: teardown deliberately does
	# NOT resume, so the filter is already gone when stop() runs.
	source = NvdaSilentSpeechSource()
	source.start(SpeechBuffer(clock, exact_finish=False), lambda: 0)
	source.suspend()
	source.stop()
	assert balanced(nvda_stubs.log.messages)
