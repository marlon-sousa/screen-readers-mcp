# Unit tests for domain/controllers/commands/get_last_speech.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from fakes.clock import FakeClock
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.get_last_speech import GetLastSpeechHandler
from support.context import make_context, request, speech_with


def test_get_last_speech(clock: FakeClock) -> None:
	ctx = make_context(clock, speech=speech_with(clock, "one", "last"))
	result = GetLastSpeechHandler().execute(ctx, request("getLastSpeech"))
	assert isinstance(result, p.LastSpeechResult)
	assert result.text == "last"
	assert result.index == 2


def test_it_carries_the_wall_clock_it_was_emitted_at(clock: FakeClock) -> None:
	clock.advance(1_755_000_000)
	ctx = make_context(clock, speech=speech_with(clock, "one", "last"))
	result = GetLastSpeechHandler().execute(ctx, request("getLastSpeech"))
	assert isinstance(result, p.LastSpeechResult)
	assert result.emittedAt


def test_the_empty_sentinel_reports_no_instant(clock: FakeClock) -> None:
	# Nothing has been said, so index 0 comes back -- and it was never emitted.
	# An empty string says that; a 1970 date would read as a real utterance.
	clock.advance(1_755_000_000)
	ctx = make_context(clock, speech=speech_with(clock))
	result = GetLastSpeechHandler().execute(ctx, request("getLastSpeech"))
	assert isinstance(result, p.LastSpeechResult)
	assert result.index == 0
	assert result.emittedAt == ""
