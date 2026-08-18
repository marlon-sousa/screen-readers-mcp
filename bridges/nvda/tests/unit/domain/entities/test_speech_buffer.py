# Unit tests for domain/entities/speech_buffer.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# Only what SpeechBuffer adds on top of IndexedBuffer: rendering a speech
# sequence, the search/wait predicates, the two "speech has finished"
# semantics, and the observer. The base's index bookkeeping is tested in
# test_indexed_buffer.py.
#
# The `clock` fixture (conftest) is the same object these buffers were built
# on, so a test that advances time is advancing the buffer's own clock by
# construction. See AGENTS.md ("Testing").

from __future__ import annotations

import pytest
from fakes.clock import FakeClock
from fakes.continuous_read import FakeContinuousRead
from nvdaMcpBridge.domain.entities.indexed_buffer import POLL_INTERVAL
from nvdaMcpBridge.domain.entities.speech_buffer import SPEECH_FINISHED_SECONDS, SpeechBuffer


@pytest.fixture
def speech(clock: FakeClock) -> SpeechBuffer:
	"""A live-mode buffer: "finished" falls back to the elapsed heuristic."""
	return SpeechBuffer(clock)


@pytest.fixture
def silent_speech(clock: FakeClock) -> SpeechBuffer:
	"""A silent-mode buffer: "finished" needs the exact synthDoneSpeaking."""
	return SpeechBuffer(clock, exact_finish=True)


# -- the grace window (spec 0025) ---------------------------------------------


def test_collect_since_returns_at_once_when_words_are_already_there(
	clock: FakeClock, speech: SpeechBuffer
) -> None:
	speech.append(["already said"])

	entries, from_index, to_index = speech.collect_since(1, grace=0.1)

	assert [text for text, _index, _pos, _at in entries] == ["already said"]
	assert (from_index, to_index) == (1, 2)
	# It never slept: the words were there when it looked.
	assert clock.sleeps == []


def test_collect_since_waits_out_the_grace_when_nothing_arrives(
	clock: FakeClock, speech: SpeechBuffer
) -> None:
	entries, from_index, to_index = speech.collect_since(1, grace=0.1)

	# An EMPTY result, not a blocked call and not a claim: "nothing had arrived
	# by then" is a fact about an instant the caller chose (spec 0025 Part 2).
	assert entries == []
	assert (from_index, to_index) == (1, 1)
	assert sum(clock.sleeps) >= 0.1 - 1e-9


def test_collect_since_ignores_speech_before_the_bookmark(speech: SpeechBuffer) -> None:
	# Background chatter that arrived before the key went out must not be read
	# as the key's answer -- the whole reason the bookmark is taken first.
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
	# The distinction the whole spec turns on. wait_to_finish asks "has speech
	# STOPPED?" and answers from a stale timestamp -- here it says yes about a
	# buffer that has never held a word. collect_since asks "has speech
	# STARTED?" and reports the same silence as an empty observation instead.
	clock.advance(SPEECH_FINISHED_SECONDS + 1)

	assert speech.wait_to_finish(timeout=0.0) is True
	assert speech.collect_since(1, grace=0.05)[0] == []


# -- rendering ----------------------------------------------------------------


def test_sequences_keep_only_string_parts(speech: SpeechBuffer) -> None:
	# NVDA interleaves SpeechCommand objects with the spoken strings (stand-ins
	# here); only the strings are words.
	speech.append(["say", object(), "this", 42])
	assert speech.get_last() == ("say this", 1)


def test_adjacent_string_parts_are_separated_by_a_space(speech: SpeechBuffer) -> None:
	# The parts carry NO trailing spaces, because real NVDA sequences do not:
	# a Windows menu item arrives as ("Move", "indisponível", "m") -- the label,
	# its state, its accelerator. Concatenating gave "Moveindisponívelm", which
	# no reader can segment. The boundary is known only here, so it is kept here.
	#
	# The previous fixtures were ("hello ", "world") -- the space baked into the
	# first part -- so both joins produced the same string and this test could
	# not see which one ran. That is why the defect reached a live session.
	speech.append(["Move", "indisponível", "m"])
	assert speech.get_last()[0] == "Move indisponível m"


def test_whitespace_only_parts_do_not_produce_double_spaces(speech: SpeechBuffer) -> None:
	speech.append(["Google Chrome", " ", "17 de 37"])
	assert speech.get_last()[0] == "Google Chrome 17 de 37"


# -- search / wait ------------------------------------------------------------


def test_index_of_respects_exclusive_after_index(speech: SpeechBuffer) -> None:
	speech.append(["alpha"])  # index 1
	speech.append(["beta"])  # index 2
	speech.append(["alpha again"])  # index 3
	assert speech.index_of("alpha") == 1
	assert speech.index_of("alpha", after_index=1) == 3
	assert speech.index_of("missing") == -1


def test_wait_for_returns_immediately_when_already_present(clock: FakeClock, speech: SpeechBuffer) -> None:
	speech.append(["found it"])
	assert speech.wait_for("found", after_index=None, timeout=5.0) == (True, 1, "found it")
	assert clock.sleeps == []  # never had to wait


def test_wait_for_times_out_and_hands_back_a_fresh_bookmark(speech: SpeechBuffer) -> None:
	found, index, text = speech.wait_for("never", after_index=None, timeout=5.0)
	assert found is False
	assert index == speech.next_index()
	assert text == ""


# -- finish semantics ---------------------------------------------------------


def test_live_mode_finish_uses_the_elapsed_heuristic(clock: FakeClock, speech: SpeechBuffer) -> None:
	speech.append(["talking"])
	# Immediately after speech it is not finished...
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
	# Elapsed time is irrelevant in exact mode; only the done signal finishes.
	clock.advance(60.0)
	assert silent_speech.wait_to_finish(timeout=0.0) is False
	silent_speech.notify_finished()
	assert silent_speech.wait_to_finish(timeout=0.0) is True


# -- a continuous read in progress (entry 11.21) -------------------------------


def test_a_running_continuous_read_is_never_finished(clock: FakeClock) -> None:
	# The state the heuristic alone gets WRONG, and the reason this port exists.
	# NVDA hands the synth one chunk of a say all and asks for the next only when
	# the synth reports reaching it -- so between chunks nothing arrives, for as
	# long as a chunk takes to speak. To the elapsed-time rule that is
	# indistinguishable from a read that ended, and it used to answer "finished"
	# to a user who could plainly hear the reading continue.
	read = FakeContinuousRead(running=True)
	speech = SpeechBuffer(clock, exact_finish=False, continuous_read=read)
	speech.append(["the first chunk of the document"])
	clock.advance(SPEECH_FINISHED_SECONDS + 60.0)

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
	# It has to be asked repeatedly or the wait could never end: a settle that
	# cached the first answer would block for its whole timeout on any say all,
	# which is a worse failure than the one being fixed.
	read = FakeContinuousRead(running=True)
	speech = SpeechBuffer(clock, exact_finish=False, continuous_read=read)

	speech.wait_to_finish(timeout=POLL_INTERVAL * 3)

	assert read.asked > 1, "the settle asked once and cached it"


def test_without_the_port_the_buffer_behaves_exactly_as_before(
	clock: FakeClock, speech: SpeechBuffer
) -> None:
	# A bridge for a reader with no such notion passes nothing, and nothing about
	# the old answer changes -- the correction is additive.
	speech.append(["talking"])
	clock.advance(SPEECH_FINISHED_SECONDS + 0.01)

	assert speech.wait_to_finish(timeout=0.0) is True


# -- observer -----------------------------------------------------------------


def test_observer_fires_for_nonempty_appends_only(speech: SpeechBuffer) -> None:
	seen: list[str] = []
	speech.set_observer(seen.append)
	speech.append(["spoken"])
	speech.append([""])  # empty -> no observer call
	assert seen == ["spoken"]


def test_observer_can_be_unregistered(speech: SpeechBuffer) -> None:
	seen: list[str] = []
	speech.set_observer(seen.append)
	speech.append(["during"])
	speech.set_observer(None)
	speech.append(["after"])
	assert seen == ["during"]
