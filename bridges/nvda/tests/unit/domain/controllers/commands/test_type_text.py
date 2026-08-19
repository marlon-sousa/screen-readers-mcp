# Unit tests for domain/controllers/commands/type_text.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import pytest
from fakes.adapter_factory import FakeAdapterFactory
from fakes.announcer import FakeAnnouncer
from fakes.clock import FakeClock
from fakes.transcript import FakeTranscript
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.type_text import TypeTextHandler
from nvdaMcpBridge.domain.ports.state_inspector import ReaderState
from nvdaMcpBridge.domain.ports.text_typer import TypingError
from support.context import adapters_from, make_context, request, speech_with


def _typed_events(transcript: FakeTranscript) -> list[tuple[object, ...]]:
	return [event for event in transcript.events if event[0] == "type"]


def test_types_the_text_and_logs_length_only(clock: FakeClock) -> None:
	factory = FakeAdapterFactory()
	transcript = FakeTranscript()
	ctx = make_context(
		clock, transcript=transcript, adapters=adapters_from(factory), speech=speech_with(clock)
	)

	result = TypeTextHandler().execute(ctx, request("typeText", text="www.blindtec.com.br"))

	assert isinstance(result, p.TypeResult)
	# The COUNT, never the text -- typing is exactly how a secret is entered.
	assert result.typed == len("www.blindtec.com.br")
	assert factory.text_typer.typed == ["www.blindtec.com.br"]
	# The length is logged, never the text (spec 0019).
	assert _typed_events(transcript) == [("type", len("www.blindtec.com.br"))]
	for event in transcript.events:
		assert "www.blindtec.com.br" not in event


def test_mutates_reader_is_true() -> None:
	assert TypeTextHandler.mutates_reader is True


def test_typing_error_propagates(clock: FakeClock) -> None:
	factory = FakeAdapterFactory(type_fail_on=["bad"])
	transcript = FakeTranscript()
	ctx = make_context(
		clock, transcript=transcript, adapters=adapters_from(factory), speech=speech_with(clock)
	)

	with pytest.raises(TypingError):
		TypeTextHandler().execute(ctx, request("typeText", text="bad"))

	# Logged before injection, mirroring PressGestureHandler.
	assert _typed_events(transcript) == [("type", 3)]


def test_rejects_missing_text(clock: FakeClock) -> None:
	factory = FakeAdapterFactory()
	ctx = make_context(clock, adapters=adapters_from(factory), speech=speech_with(clock))
	with pytest.raises(p.ValidationError):
		TypeTextHandler().execute(ctx, request("typeText"))


def test_the_grace_defaults_to_zero_here_and_the_window_is_still_reported(
	clock: FakeClock,
) -> None:
	# Deliberately unlike pressGesture (spec 0025, settled 2026-08-16): typing
	# with "speak typed characters" on produces one utterance per character and
	# none is worth waiting for. The WINDOW is still reported, so an agent reads
	# the same shape from both tools and resumes from the same coordinate.
	factory = FakeAdapterFactory()
	speech = speech_with(clock, "background chatter")
	ctx = make_context(clock, adapters=adapters_from(factory), speech=speech)

	result = TypeTextHandler().execute(ctx, request("typeText", text="ola"))

	assert isinstance(result, p.TypeResult)
	assert result.speech == []
	assert (result.speechFrom, result.speechTo) == (2, 2)


def test_the_state_snapshot_rides_along_here_too(clock: FakeClock) -> None:
	# Four small fields, never misleading for typing -- only rarely interesting.
	# An agent pays more for the asymmetry in confusion than the bytes cost in
	# transport, so consistency IS the right call here (spec 0025).
	factory = FakeAdapterFactory()
	ctx = make_context(clock, adapters=adapters_from(factory), speech=speech_with(clock))
	factory.state_inspector.reader_state = ReaderState(
		browse_mode="none", speech_mode="off", sleep_mode=False, input_help=False
	)

	result = TypeTextHandler().execute(ctx, request("typeText", text="ola"))

	assert isinstance(result, p.TypeResult)
	assert result.state is not None
	assert result.state.speechMode == "off"


def test_the_announcement_is_spoken_before_the_text_is_injected(clock: FakeClock) -> None:
	factory = FakeAdapterFactory(type_fail_on=["secreta"])
	announcer = FakeAnnouncer()
	ctx = make_context(clock, adapters=adapters_from(factory), speech=speech_with(clock), announcer=announcer)

	with pytest.raises(TypingError):
		TypeTextHandler().execute(
			ctx, request("typeText", text="secreta", announce="about to type the phrase")
		)

	# Injection failed, so an announcement made afterwards would never have been
	# spoken. Note what it says: the narration is the agent's own words, not the
	# text -- that stays out of every artefact (spec 0019).
	assert announcer.announced == ["about to type the phrase"]
