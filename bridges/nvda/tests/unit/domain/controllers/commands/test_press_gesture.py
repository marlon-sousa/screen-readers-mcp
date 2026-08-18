# Unit tests for domain/controllers/commands/press_gesture.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import pytest
from fakes.adapter_factory import FakeAdapterFactory
from fakes.announcer import FakeAnnouncer
from fakes.clock import FakeClock
from fakes.transcript import FakeTranscript
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.press_gesture import PressGestureHandler
from nvdaMcpBridge.domain.entities.speech_buffer import SpeechBuffer
from nvdaMcpBridge.domain.ports.gesture_sender import GestureError
from nvdaMcpBridge.domain.ports.state_inspector import ReaderState
from support.context import adapters_from, make_context, request, speech_with


def _gestures(transcript: FakeTranscript) -> list[tuple[object, ...]]:
	return [event for event in transcript.events if event[0] == "gesture"]


def _wire(factory: FakeAdapterFactory, buffer: SpeechBuffer) -> None:
	"""Start the fake speech source on *buffer*, as hello does in production.

	Without this a scripted gesture has nowhere to speak: the gesture sender
	feeds the source's buffer, exactly as pressing a key makes the real NVDA
	speak through the real speech source.
	"""
	factory.speech_source.start(buffer, lambda: 0)


def test_presses_in_order_and_logs_each(clock: FakeClock) -> None:
	factory = FakeAdapterFactory()
	transcript = FakeTranscript()
	speech = speech_with(clock)
	ctx = make_context(clock, transcript=transcript, adapters=adapters_from(factory), speech=speech)
	_wire(factory, speech)

	result = PressGestureHandler().execute(ctx, request("pressGesture", gestures=["a", "b"]))

	assert isinstance(result, p.GestureResult)
	assert factory.gesture_sender.pressed == ["a", "b"]
	assert _gestures(transcript) == [("gesture", "a"), ("gesture", "b")]


def test_a_silent_gesture_reports_an_empty_span_rather_than_vanishing(clock: FakeClock) -> None:
	# The 2026-08-03 failure in miniature: five `h` presses came back as
	# {"pressed": ["h","h","h","h","h"]} with one blended speech read, so "four
	# of these said nothing" was not expressible. Now each key carries its own
	# half-open span and an empty one is the answer.
	factory = FakeAdapterFactory(speech={"a": ["said a"]})
	speech = speech_with(clock)
	ctx = make_context(clock, adapters=adapters_from(factory), speech=speech)
	_wire(factory, speech)

	result = PressGestureHandler().execute(ctx, request("pressGesture", gestures=["h", "a", "h"]))

	assert isinstance(result, p.GestureResult)
	assert [(press.gesture, press.speechFrom, press.speechTo) for press in result.pressed] == [
		("h", 1, 1),
		("a", 1, 2),
		("h", 2, 2),
	]
	assert [entry.text for entry in result.speech] == ["said a"]
	# The aggregate window is what the caller resumes from, with no gap.
	assert (result.speechFrom, result.speechTo) == (1, 2)


def test_an_empty_window_is_a_fact_about_an_instant_not_a_claim(clock: FakeClock) -> None:
	# Spec 0025 Part 2: a result says what had arrived by a stated instant and
	# where to resume -- never that this is all there is. So a silent call is
	# an empty list plus a usable resume point, and there is no `complete` flag
	# anywhere on the shape to tempt an agent into reading one.
	factory = FakeAdapterFactory()
	speech = speech_with(clock)
	ctx = make_context(clock, adapters=adapters_from(factory), speech=speech)
	_wire(factory, speech)

	result = PressGestureHandler().execute(ctx, request("pressGesture", gestures=["h"]))

	assert isinstance(result, p.GestureResult)
	assert result.speech == []
	assert result.speechTo == speech.next_index()
	assert not hasattr(result, "complete")
	assert not hasattr(result, "finished")


def test_zero_grace_opts_out_and_still_reports_the_window(clock: FakeClock) -> None:
	factory = FakeAdapterFactory(speech={"a": ["said a"]})
	speech = speech_with(clock)
	ctx = make_context(clock, adapters=adapters_from(factory), speech=speech)
	_wire(factory, speech)

	result = PressGestureHandler().execute(ctx, request("pressGesture", gestures=["a"], graceMs=0))

	# The fake speaks synchronously inside press(), so even with no wait the
	# words are already there -- what this pins is that opting out reports the
	# ring as it stands rather than skipping the observation entirely.
	assert isinstance(result, p.GestureResult)
	assert [entry.text for entry in result.speech] == ["said a"]
	assert (result.speechFrom, result.speechTo) == (1, 2)


def test_the_announcement_is_spoken_before_anything_is_dispatched(clock: FakeClock) -> None:
	# 11.10's protection must not be the thing that costs the most, so the
	# narration rides along instead of doubling the call count. That it comes
	# FIRST is the part that matters to a mute tester, and this proves it
	# behaviourally: the only gesture is rejected, so nothing is ever pressed --
	# an announcement made after dispatch would never have been spoken.
	factory = FakeAdapterFactory(reject=["bad"])
	speech = speech_with(clock)
	announcer = FakeAnnouncer()
	ctx = make_context(clock, adapters=adapters_from(factory), speech=speech, announcer=announcer)
	_wire(factory, speech)

	with pytest.raises(GestureError):
		PressGestureHandler().execute(
			ctx, request("pressGesture", gestures=["bad"], announce="about to press bad")
		)

	assert announcer.announced == ["about to press bad"]


def test_a_blank_announcement_says_nothing(clock: FakeClock) -> None:
	factory = FakeAdapterFactory()
	speech = speech_with(clock)
	announcer = FakeAnnouncer()
	ctx = make_context(clock, adapters=adapters_from(factory), speech=speech, announcer=announcer)
	_wire(factory, speech)

	PressGestureHandler().execute(ctx, request("pressGesture", gestures=["a"], announce="   "))

	assert announcer.announced == []


def test_the_state_snapshot_rides_on_the_result(clock: FakeClock) -> None:
	# It answers 0024's question -- did something happen this session cannot
	# HEAR -- and is deliberately not focus information (0023, upheld by 0025
	# Part 3.3). Sampled once, at the close of the last window.
	factory = FakeAdapterFactory()
	speech = speech_with(clock)
	ctx = make_context(clock, adapters=adapters_from(factory), speech=speech)
	_wire(factory, speech)
	factory.state_inspector.reader_state = ReaderState(
		browse_mode="browse", speech_mode="talk", sleep_mode=False, input_help=False
	)

	result = PressGestureHandler().execute(ctx, request("pressGesture", gestures=["a", "b"]))

	assert isinstance(result, p.GestureResult)
	assert result.state is not None
	assert result.state.browseMode is p.BrowseMode.BROWSE
	assert len(factory.state_inspector.calls) == 1


def test_mutates_reader_is_true() -> None:
	# A keypress moves the user's machine, so an observe-only session (spec
	# 0017) must refuse it -- the same gate typeText and setConfig ride.
	assert PressGestureHandler.mutates_reader is True


def test_gesture_error_aborts_the_remainder(clock: FakeClock) -> None:
	factory = FakeAdapterFactory(reject=["bad"])
	transcript = FakeTranscript()
	speech = speech_with(clock)
	ctx = make_context(clock, transcript=transcript, adapters=adapters_from(factory), speech=speech)
	_wire(factory, speech)

	with pytest.raises(GestureError):
		PressGestureHandler().execute(ctx, request("pressGesture", gestures=["a", "bad", "c"]))

	# "a" pressed, "bad" rejected, "c" never reached; "a" and "bad" both logged
	# (the transcript entry precedes the press).
	assert factory.gesture_sender.pressed == ["a"]
	assert _gestures(transcript) == [("gesture", "a"), ("gesture", "bad")]
