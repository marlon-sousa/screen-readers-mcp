# Unit tests for domain/controllers/commands/get_speech.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# The result is a LIST of entries, not a joined blob (spec 0021): each utterance
# crosses the wire once, carrying its own index and the journal position it was
# captured at, so a caller can place it on the log's timeline. The blob could not
# do that -- three Down presses make three utterances and one string, so whichever
# utterance's position you stored, the other two had none.

from __future__ import annotations

from fakes.clock import FakeClock
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.get_speech import GetSpeechHandler
from support.context import make_context, request, speech_with


def test_get_speech_reads_since_index(clock: FakeClock) -> None:
	ctx = make_context(clock, speech=speech_with(clock, "one", "two"))
	result = GetSpeechHandler().execute(ctx, request("getSpeech", sinceIndex=0))
	assert isinstance(result, p.SpeechResult)
	assert [entry.text for entry in result.entries] == ["one", "two"]
	assert result.fromIndex == 0
	assert result.toIndex == 3


def test_each_entry_carries_its_own_index(clock: FakeClock) -> None:
	# The index is the entry's own place in the ring, not its place in the answer:
	# empty renders are dropped, so position i in the list is NOT fromIndex + i.
	ctx = make_context(clock, speech=speech_with(clock, "one", "two"))
	result = GetSpeechHandler().execute(ctx, request("getSpeech", sinceIndex=0))
	assert isinstance(result, p.SpeechResult)
	assert [entry.index for entry in result.entries] == [1, 2]


def test_each_entry_carries_the_journal_position_it_was_captured_at(
	clock: FakeClock,
) -> None:
	ctx = make_context(clock, speech=speech_with(clock, "one", "two", log_positions=[41, 87]))
	result = GetSpeechHandler().execute(ctx, request("getSpeech", sinceIndex=0))
	assert isinstance(result, p.SpeechResult)
	assert [entry.logPosition for entry in result.entries] == [41, 87]


def test_a_bookmark_past_the_end_returns_nothing(clock: FakeClock) -> None:
	ctx = make_context(clock, speech=speech_with(clock, "one"))
	result = GetSpeechHandler().execute(ctx, request("getSpeech", sinceIndex=99))
	assert isinstance(result, p.SpeechResult)
	assert result.entries == []
