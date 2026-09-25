# Unit tests for the three capture source adapters' journal coordinate.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from collections.abc import Iterator

import pytest
from fakes.clock import FakeClock
from support import nvda_stubs

nvda_stubs.install()

from nvdaMcpBridge.adapters.nvda_braille_source import NvdaBrailleSource
from nvdaMcpBridge.adapters.nvda_live_speech_source import NvdaLiveSpeechSource
from nvdaMcpBridge.adapters.nvda_silent_speech_source import (
	RESTORED_MARKER,
	SUPPRESSED_MARKER,
	NvdaSilentSpeechSource,
)
from nvdaMcpBridge.domain.entities.braille_buffer import BrailleBuffer
from nvdaMcpBridge.domain.entities.speech_buffer import SpeechBuffer


class MovingJournal:
	"""Advances on every read, so a cached position shows up as a repeated integer."""

	def __init__(self) -> None:
		self.position = 0

	def __call__(self) -> int:
		self.position += 1
		return self.position


def _positions(buffer: SpeechBuffer | BrailleBuffer) -> list[int]:
	return [entry[2] for entry in buffer.entries_since(1)[0]]


@pytest.fixture(autouse=True)
def clean_extension_points() -> Iterator[None]:
	"""No registration outlives its test; NVDA's real points are process-wide."""
	yield
	nvda_stubs.reset()


def test_the_silent_source_stamps_each_utterance_as_it_captures(clock: FakeClock) -> None:
	buffer = SpeechBuffer(clock, exact_finish=False)
	journal = MovingJournal()
	source = NvdaSilentSpeechSource()
	source.start(buffer, journal)

	handler = nvda_stubs.filter_speechSequence.handlers[0]
	handler(["first"])
	handler(["second"])

	assert _positions(buffer) == [1, 2], "the position was read once, not per capture"


def test_the_silent_source_still_suppresses_while_stamping(clock: FakeClock) -> None:
	buffer = SpeechBuffer(clock, exact_finish=False)
	source = NvdaSilentSpeechSource()
	source.start(buffer, MovingJournal())

	handler = nvda_stubs.filter_speechSequence.handlers[0]

	assert handler(["something audible"]) == []
	assert _positions(buffer) == [1]


def test_the_silent_source_marks_the_users_own_log_once_per_session(clock: FakeClock) -> None:
	source = NvdaSilentSpeechSource()
	source.start(SpeechBuffer(clock, exact_finish=False), MovingJournal())
	handler = nvda_stubs.filter_speechSequence.handlers[0]
	handler(["one"])
	handler(["two"])
	source.stop()

	assert nvda_stubs.log.messages == [SUPPRESSED_MARKER, RESTORED_MARKER]


def test_an_interaction_window_does_not_re_mark_the_log(clock: FakeClock) -> None:
	source = NvdaSilentSpeechSource()
	source.start(SpeechBuffer(clock, exact_finish=False), MovingJournal())
	source.suspend()
	source.resume()
	source.stop()

	assert nvda_stubs.log.messages == [SUPPRESSED_MARKER, RESTORED_MARKER]


def test_a_source_that_never_started_does_not_claim_it_restored_speech() -> None:
	NvdaSilentSpeechSource().stop()

	assert nvda_stubs.log.messages == []


def test_the_markers_balance_even_when_teardown_finds_a_window_open(clock: FakeClock) -> None:
	# Teardown does not resume a window left open, so stop() finds the filter already unregistered.
	source = NvdaSilentSpeechSource()
	source.start(SpeechBuffer(clock, exact_finish=False), MovingJournal())
	source.suspend()  # an interaction window opened, and nothing resumed it
	source.stop()

	assert nvda_stubs.log.messages == [SUPPRESSED_MARKER, RESTORED_MARKER]


def test_stopping_twice_does_not_claim_speech_was_restored_twice(clock: FakeClock) -> None:
	source = NvdaSilentSpeechSource()
	source.start(SpeechBuffer(clock, exact_finish=False), MovingJournal())
	source.stop()
	source.stop()

	assert nvda_stubs.log.messages == [SUPPRESSED_MARKER, RESTORED_MARKER]


def test_the_live_source_stamps_each_utterance_as_it_captures(clock: FakeClock) -> None:
	buffer = SpeechBuffer(clock, exact_finish=False)
	source = NvdaLiveSpeechSource()
	source.start(buffer, MovingJournal())

	handler = nvda_stubs.pre_speechQueued.handlers[0]
	handler(speechSequence=["first"])
	handler(speechSequence=["second"])

	assert _positions(buffer) == [1, 2]


def test_the_live_source_leaves_the_sequence_alone(clock: FakeClock) -> None:
	buffer = SpeechBuffer(clock, exact_finish=False)
	source = NvdaLiveSpeechSource()
	source.start(buffer, MovingJournal())

	assert nvda_stubs.pre_speechQueued.handlers[0](speechSequence=["audible"]) is None
	assert buffer.get_last()[0] == "audible"


def test_the_braille_source_stamps_each_update_as_it_captures(clock: FakeClock) -> None:
	buffer = BrailleBuffer(clock)
	source = NvdaBrailleSource()
	source.start(buffer, MovingJournal())

	handler = nvda_stubs.pre_writeCells.handlers[0]
	handler(cells=[], rawText="find: x", currentCellCount=40)
	handler(cells=[], rawText="find: xy", currentCellCount=40)

	assert _positions(buffer) == [1, 2]


def test_an_unstarted_source_stamps_zero_rather_than_raising(clock: FakeClock) -> None:
	# NVDA fires handlers on its own threads, so a capture can precede start().
	source = NvdaBrailleSource()
	source._on_write_cells(rawText="nobody is listening")  # type: ignore[attr-defined]
