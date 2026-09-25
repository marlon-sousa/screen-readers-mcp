# Unit tests for domain/entities/speech_buffer.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import pytest
from fakes.clock import FakeClock
from fakes.continuous_read import FakeContinuousRead
from nvdaMcpBridge.domain.entities.indexed_buffer import POLL_INTERVAL
from nvdaMcpBridge.domain.entities.speech_buffer import (
	CONTINUOUS_READ_STALE_SECONDS,
	SPEECH_FINISHED_SECONDS,
	SpeechBuffer,
)


@pytest.fixture
def speech(clock: FakeClock) -> SpeechBuffer:
	"""A live-mode buffer: "finished" falls back to the elapsed heuristic."""
	return SpeechBuffer(clock)


@pytest.fixture
def silent_speech(clock: FakeClock) -> SpeechBuffer:
	"""A silent-mode buffer: "finished" needs the exact synthDoneSpeaking."""
	return SpeechBuffer(clock, exact_finish=True)


def test_collect_since_returns_at_once_when_words_are_already_there(
	clock: FakeClock, speech: SpeechBuffer
) -> None:
	speech.append(["already said"])

	entries, from_index, to_index = speech.collect_since(1, grace=0.1)

	assert [text for text, _index, _pos, _at in entries] == ["already said"]
	assert (from_index, to_index) == (1, 2)
	assert clock.sleeps == []


def test_collect_since_waits_out_the_grace_when_nothing_arrives(
	clock: FakeClock, speech: SpeechBuffer
) -> None:
	entries, from_index, to_index = speech.collect_since(1, grace=0.1)

	assert entries == []
	assert (from_index, to_index) == (1, 1)
	assert sum(clock.sleeps) >= 0.1 - 1e-9


def test_collect_since_ignores_speech_before_the_bookmark(speech: SpeechBuffer) -> None:
	speech.append(["chatter from before"])

	entries, from_index, _to_index = speech.collect_since(speech.next_index(), grace=0.05)

	assert entries == []
	assert from_index == 2


def test_a_zero_grace_reads_the_buffer_without_sleeping(clock: FakeClock, speech: SpeechBuffer) -> None:
	speech.append(["said"])

	entries, _from_index, _to_index = speech.collect_since(1, grace=0.0)

	assert [text for text, _index, _pos, _at in entries] == ["said"]
	assert clock.sleeps == []


def test_collect_since_is_not_the_settle(clock: FakeClock, speech: SpeechBuffer) -> None:
	# wait_to_finish answers from a stale timestamp; collect_since reports the same silence as empty.
	clock.advance(SPEECH_FINISHED_SECONDS + 1)

	assert speech.wait_to_finish(timeout=0.0) is True
	assert speech.collect_since(1, grace=0.05)[0] == []


def test_index_of_treats_after_index_as_an_inclusive_left_edge(speech: SpeechBuffer) -> None:
	speech.append(["alpha"])
	speech.append(["beta"])
	speech.append(["alpha again"])
	assert speech.index_of("alpha") == 1
	# The entry at the edge matches: the bookmark names index 1, and index 1 is what must be found.
	assert speech.index_of("alpha", after_index=1) == 1
	assert speech.index_of("missing") == -1


def test_index_of_excludes_everything_left_of_the_edge(speech: SpeechBuffer) -> None:
	speech.append(["alpha"])
	speech.append(["beta"])
	speech.append(["alpha again"])
	assert speech.index_of("alpha", after_index=2) == 3
	assert speech.index_of("alpha", after_index=4) == -1


def test_index_of_clamps_a_negative_edge(speech: SpeechBuffer) -> None:
	"""Without the clamp an inclusive edge would slice from the end of the list."""
	speech.append(["alpha"])
	assert speech.index_of("alpha", after_index=-5) == 1


def test_index_of_no_constraint_and_zero_agree(speech: SpeechBuffer) -> None:
	"""Index 0 is the empty sentinel, so the two requests coincide harmlessly."""
	speech.append(["alpha"])
	assert speech.index_of("alpha", after_index=0) == speech.index_of("alpha") == 1


def test_wait_for_returns_immediately_when_already_present(clock: FakeClock, speech: SpeechBuffer) -> None:
	speech.append(["found it"])
	assert speech.wait_for("found", after_index=None, timeout=5.0) == (True, 1, "found it")
	assert clock.sleeps == []


def test_wait_for_times_out_and_hands_back_a_fresh_bookmark(speech: SpeechBuffer) -> None:
	found, index, text = speech.wait_for("never", after_index=None, timeout=5.0)
	assert found is False
	assert index == speech.next_index()
	assert text == ""


def test_live_mode_finish_uses_the_elapsed_heuristic(clock: FakeClock, speech: SpeechBuffer) -> None:
	speech.append(["talking"])
	assert speech._has_finished() is False  # type: ignore[attr-defined]
	clock.advance(SPEECH_FINISHED_SECONDS + 0.01)
	assert speech._has_finished() is True  # type: ignore[attr-defined]


def test_live_mode_wait_to_finish_true_after_a_quiet_period(speech: SpeechBuffer) -> None:
	speech.append(["talking"])
	assert speech.wait_to_finish(timeout=5.0) is True


def test_silent_mode_finish_waits_for_the_synth_done_signal(
	clock: FakeClock, silent_speech: SpeechBuffer
) -> None:
	silent_speech.append(["talking"])
	clock.advance(60.0)
	assert silent_speech.wait_to_finish(timeout=0.0) is False
	silent_speech.notify_finished()
	assert silent_speech.wait_to_finish(timeout=0.0) is True


def test_a_gap_longer_than_the_heuristic_is_not_the_end_of_a_read(clock: FakeClock) -> None:
	# NVDA asks for the next say-all chunk only when the synth reaches the current one, so nothing
	# arrives between chunks for as long as a chunk takes to speak.
	read = FakeContinuousRead(running=True)
	speech = SpeechBuffer(clock, exact_finish=False, continuous_read=read)
	speech.append(["the first chunk of the document"])
	# NVDA 2026.1 with ibmeci leaves a 2.0 s gap between say-all chunks.
	clock.advance(2.0)

	assert speech.wait_to_finish(timeout=0.0) is False, "a say all between chunks was reported finished"


def test_the_settle_finishes_once_the_continuous_read_ends(clock: FakeClock) -> None:
	read = FakeContinuousRead(running=True)
	speech = SpeechBuffer(clock, exact_finish=False, continuous_read=read)
	speech.append(["the last chunk"])
	clock.advance(SPEECH_FINISHED_SECONDS + 0.01)
	assert speech.wait_to_finish(timeout=0.0) is False

	read.running = False

	assert speech.wait_to_finish(timeout=0.0) is True


def test_the_read_is_asked_again_on_every_poll(clock: FakeClock) -> None:
	# A settle that cached the first answer would block for its whole timeout on any say all.
	read = FakeContinuousRead(running=True)
	speech = SpeechBuffer(clock, exact_finish=False, continuous_read=read)

	speech.wait_to_finish(timeout=POLL_INTERVAL * 3)

	assert read.asked > 1, "the settle asked once and cached it"


def test_without_the_port_the_buffer_behaves_exactly_as_before(
	clock: FakeClock, speech: SpeechBuffer
) -> None:
	speech.append(["talking"])
	clock.advance(SPEECH_FINISHED_SECONDS + 0.01)

	assert speech.wait_to_finish(timeout=0.0) is True


def test_a_claimed_read_cannot_hold_the_settle_open_for_ever(clock: FakeClock) -> None:
	# The port speaks for a reader we do not control, so a stuck in-progress answer must expire.
	read = FakeContinuousRead(running=True)
	speech = SpeechBuffer(clock, exact_finish=False, continuous_read=read)
	speech.append(["a chunk"])

	clock.advance(CONTINUOUS_READ_STALE_SECONDS - 0.01)
	assert speech.wait_to_finish(timeout=0.0) is False, "cut a genuine read short"

	clock.advance(0.02)

	assert speech.wait_to_finish(timeout=0.0) is True, (
		"a stuck in-progress answer held the settle open indefinitely"
	)


def test_observer_fires_for_nonempty_appends_only(speech: SpeechBuffer) -> None:
	seen: list[str] = []
	speech.set_observer(seen.append)
	speech.append(["spoken"])
	speech.append([""])
	assert seen == ["spoken"]


def test_observer_can_be_unregistered(speech: SpeechBuffer) -> None:
	seen: list[str] = []
	speech.set_observer(seen.append)
	speech.append(["during"])
	speech.set_observer(None)
	speech.append(["after"])
	assert seen == ["during"]
