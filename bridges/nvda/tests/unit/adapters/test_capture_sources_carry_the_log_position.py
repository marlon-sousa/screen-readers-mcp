# Unit tests for the three capture source adapters' journal coordinate.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# Spec 0021's item 14, adapter side: an entry's `logPosition` is only worth
# anything if the adapter reads it AT THE MOMENT OF CAPTURE. An adapter that
# forgot the call, or that read the position once at start() and reused it, would
# ship a constant integer that looks perfectly valid on the wire and places every
# utterance at the same point on the log's timeline. No behavioural test upstream
# of these three files can tell that apart from the real thing, because the
# buffers faithfully store whatever they are handed.
#
# All three adapters are on pyright's ignore list (they import NVDA), so NVDA's
# speech and braille extension points are stubbed from support/nvda_stubs.py,
# which is also where test_nvda_log_capture.py gets its logHandler. A stub point
# keeps the handlers NVDA would hold and lets a test fire them, which is exactly
# what NVDA does at the moment of capture.

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
	"""A journal position that advances every time it is read.

	The point of the fake: an adapter that reads the position once and caches it
	is indistinguishable from a correct one against a CONSTANT, so this makes any
	staleness show up as a repeated integer.
	"""

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


# -- silent mode ---------------------------------------------------------------


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
	# The coordinate must not have cost the feature: the filter still returns an
	# emptied sequence, so speak() stops before the synth.
	buffer = SpeechBuffer(clock, exact_finish=False)
	source = NvdaSilentSpeechSource()
	source.start(buffer, MovingJournal())

	handler = nvda_stubs.filter_speechSequence.handlers[0]

	assert handler(["something audible"]) == []
	assert _positions(buffer) == [1]


def test_the_silent_source_marks_the_users_own_log_once_per_session(clock: FakeClock) -> None:
	# A silent run drops NVDA's speech records from the log entirely -- our filter
	# empties the sequence before speech.speak reaches its own log.io line -- which
	# reads, in the human's nvda.log, like an NVDA fault rather than our doing. One
	# marker per SESSION, not per utterance: at `io` a chatty minute would bury the
	# log in our own noise (spec 0021).
	source = NvdaSilentSpeechSource()
	source.start(SpeechBuffer(clock, exact_finish=False), MovingJournal())
	handler = nvda_stubs.filter_speechSequence.handlers[0]
	handler(["one"])
	handler(["two"])
	source.stop()

	assert nvda_stubs.log.messages == [SUPPRESSED_MARKER, RESTORED_MARKER]


def test_an_interaction_window_does_not_re_mark_the_log(clock: FakeClock) -> None:
	# suspend/resume are about one interaction window, not the session, so they
	# stay silent -- otherwise every askUser would add a pair of markers.
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
	# The path that made a separate flag necessary. Teardown deliberately does NOT
	# resume() a session dying with an interaction window open -- resuming would
	# re-suppress and could strand the tester mute -- so stop() finds the filter
	# already unregistered. Keyed off that alone, it wrote "suppressed" and never
	# "restored", leaving the human's own nvda.log claiming a suppression that had
	# in fact ended. That unexplained state is the exact thing the markers exist
	# to prevent, so the pair has to balance on every path.
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


# -- live mode -----------------------------------------------------------------


def test_the_live_source_stamps_each_utterance_as_it_captures(clock: FakeClock) -> None:
	# Both capture modes, the spec says -- and they use different NVDA hooks, so
	# getting it right in one proves nothing about the other.
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


# -- braille (one source, both modes) -----------------------------------------


def test_the_braille_source_stamps_each_update_as_it_captures(clock: FakeClock) -> None:
	buffer = BrailleBuffer(clock)
	source = NvdaBrailleSource()
	source.start(buffer, MovingJournal())

	handler = nvda_stubs.pre_writeCells.handlers[0]
	handler(cells=[], rawText="find: x", currentCellCount=40)
	handler(cells=[], rawText="find: xy", currentCellCount=40)

	assert _positions(buffer) == [1, 2]


def test_an_unstarted_source_stamps_zero_rather_than_raising(clock: FakeClock) -> None:
	# The default provider matters: a capture that fires before start() (NVDA holds
	# handlers weakly and fires on its own threads) must not take the session down.
	source = NvdaBrailleSource()
	source._on_write_cells(rawText="nobody is listening")  # type: ignore[attr-defined]
