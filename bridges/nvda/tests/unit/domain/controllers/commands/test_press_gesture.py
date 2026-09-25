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
	"""Start the fake speech source on *buffer*, as hello does in production."""
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
	assert (result.speechFrom, result.speechTo) == (1, 2)


def test_an_empty_window_is_a_fact_about_an_instant_not_a_claim(clock: FakeClock) -> None:
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

	# The fake speaks synchronously inside press().
	assert isinstance(result, p.GestureResult)
	assert [entry.text for entry in result.speech] == ["said a"]
	assert (result.speechFrom, result.speechTo) == (1, 2)


def test_the_announcement_is_spoken_before_anything_is_dispatched(clock: FakeClock) -> None:
	# The only gesture is rejected, so an announcement made after dispatch would never be spoken.
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
	assert PressGestureHandler.mutates_reader is True


def test_gesture_error_aborts_the_remainder(clock: FakeClock) -> None:
	factory = FakeAdapterFactory(reject=["bad"])
	transcript = FakeTranscript()
	speech = speech_with(clock)
	ctx = make_context(clock, transcript=transcript, adapters=adapters_from(factory), speech=speech)
	_wire(factory, speech)

	with pytest.raises(GestureError):
		PressGestureHandler().execute(ctx, request("pressGesture", gestures=["a", "bad", "c"]))

	# The transcript entry precedes the press.
	assert factory.gesture_sender.pressed == ["a"]
	assert _gestures(transcript) == [("gesture", "a"), ("gesture", "bad")]
