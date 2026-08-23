# Unit tests for domain/controllers/commands/wait_for_speech.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from fakes.clock import FakeClock
from nvdaMcpBridge.domain.controllers.commands.wait_for_speech import WaitForSpeechHandler
from support.context import make_context, request, speech_with


def test_wait_for_speech_found(clock: FakeClock) -> None:
	ctx = make_context(clock, speech=speech_with(clock, "Find dialog"))
	result = WaitForSpeechHandler().execute(
		ctx, request("waitForSpeech", text="Find", afterIndex=0, timeout=1.0)
	)
	assert result.found is True
	assert "Find" in result.text


def test_the_bookmark_act_wait_pattern_finds_the_first_utterance_the_action_caused(
	clock: FakeClock,
) -> None:
	"""Entry 11.29, at the handler: the taught pattern must not skip its own hit.

	Every description teaches bookmark, act, wait on that bookmark. Here the
	bookmark is taken while the buffer is empty -- so it names index 1 -- and the
	action then produces exactly one utterance, which lands AT index 1. Under the
	exclusive edge this timed out, reporting the reader had never spoken.
	"""
	speech = speech_with(clock)
	bookmark = speech.next_index()
	ctx = make_context(clock, speech=speech)
	speech.append(["Find dialog"])  # the action's first and only utterance

	result = WaitForSpeechHandler().execute(
		ctx, request("waitForSpeech", text="Find", afterIndex=bookmark, timeout=1.0)
	)
	assert result.found is True
	assert result.index == bookmark
	assert "Find" in result.text


def test_wait_for_speech_not_found_returns_a_fresh_bookmark(clock: FakeClock) -> None:
	ctx = make_context(clock, speech=speech_with(clock, "hello"))
	result = WaitForSpeechHandler().execute(
		ctx, request("waitForSpeech", text="absent", afterIndex=0, timeout=0.0)
	)
	assert result.found is False
	assert result.text == ""


def test_a_match_carries_the_wall_clock_it_was_emitted_at(clock: FakeClock) -> None:
	clock.advance(1_755_000_000)
	ctx = make_context(clock, speech=speech_with(clock, "Find dialog"))
	result = WaitForSpeechHandler().execute(
		ctx, request("waitForSpeech", text="Find", afterIndex=0, timeout=1.0)
	)
	assert result.found is True
	assert result.emittedAt


def test_a_miss_reports_no_instant_even_though_it_keeps_a_bookmark(clock: FakeClock) -> None:
	# index and logPosition stay useful on a miss -- they are a "from here" mark.
	# emittedAt cannot be: nothing was emitted, and reporting "now" would read as
	# a match that happened (spec 0028).
	clock.advance(1_755_000_000)
	ctx = make_context(clock, speech=speech_with(clock, "hello"))
	result = WaitForSpeechHandler().execute(
		ctx, request("waitForSpeech", text="nothing like this", afterIndex=0, timeout=0.0)
	)
	assert result.found is False
	assert result.emittedAt == ""
