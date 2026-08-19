# Unit tests for what silent mode must NOT swallow along with the words.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# Found live on 2026-08-18 (board entry 11.13): say all read two chunks in a
# silent session and stopped. The cause was ours. A speech sequence is not only
# words -- NVDA clocks some of its own machinery on the BaseCallbackCommands
# inside it, and say all is the clearest case: speech/sayAll.py inserts a
# CallbackCommand at position 0 of every chunk, and that callback is what moves
# the caret and asks for the next chunk. Emptying the sequence deleted it, and
# speech.speak() then returns early on the empty sequence, so the speech manager
# -- the thing that would have turned the callback into an index -- never saw it.
# Say all sat waiting for a lineReached that could not arrive.
#
# So these tests guard three properties, and the second is not decoration:
#
#   1. callbacks still run, or a silent session cannot read a document at all;
#   2. they run QUEUED, never inline -- lineReached calls nextLine calls speak,
#      which lands straight back in the filter, so inline is unbounded recursion
#      on NVDA's main thread. A test that only checked "the callback ran" passes
#      against the version that crashes NVDA;
#   3. beeps and wave files stay silent, because they are callbacks too and
#      running those would break the one promise a silent session makes.
#
# Why not pass the callbacks through to the synth instead, and let NVDA's own
# index machinery run them? Because that makes correctness depend on how the
# tester's synth treats a text-free utterance, and the drivers disagree: espeak,
# oneCore, RHVoice and ibmeci all report indexes from an audio callback, so no
# audio can mean no index, and NVDA's own manager names oneCore as a synth that
# skips indexes with no text between them. NVDA's "No speech" driver notifies
# nobody at all. Running them here is the only mechanism independent of that
# choice -- which is what makes it testable here, without a synth.

from __future__ import annotations

from collections.abc import Callable, Iterator
from typing import Any

import pytest
from fakes.clock import FakeClock
from support import nvda_stubs

nvda_stubs.install()

from nvdaMcpBridge.adapters.nvda_silent_speech_source import NvdaSilentSpeechSource
from nvdaMcpBridge.domain.entities.speech_buffer import SpeechBuffer


@pytest.fixture(autouse=True)
def clean_extension_points() -> Iterator[None]:
	"""No registration outlives its test; NVDA's real points are process-wide."""
	yield
	nvda_stubs.reset()


#: What NVDA calls: a sequence in, the sequence it may speak out.
SpeechFilter = Callable[[list[Any]], list[Any]]


@pytest.fixture
def filter_handler(clock: FakeClock) -> Iterator[SpeechFilter]:
	"""A started silent source, handed back as the filter NVDA would call."""
	source = NvdaSilentSpeechSource()
	source.start(SpeechBuffer(clock, exact_finish=False), lambda: 0)
	# NVDA holds filter handlers by WEAK reference, so the source has to outlive
	# the fixture or the handler dies before the test runs; the generator's own
	# frame is what keeps it alive.
	yield nvda_stubs.filter_speechSequence.handlers[0]
	source.stop()


def test_a_callback_in_the_sequence_still_runs(filter_handler: SpeechFilter) -> None:
	ran: list[str] = []
	command = nvda_stubs.StubCallbackCommand(lambda: ran.append("say-all:lineReached"))

	filter_handler(["a line", command])
	nvda_stubs.eventQueue.pump()

	assert ran == ["say-all:lineReached"], "the callback was swallowed with the words; say all cannot advance"


def test_the_callback_is_queued_rather_than_run_inline(filter_handler: SpeechFilter) -> None:
	ran: list[str] = []
	command = nvda_stubs.StubCallbackCommand(lambda: ran.append("ran"))

	filter_handler([command])

	assert ran == [], "the callback ran inside the filter; say all would recurse here"
	assert len(nvda_stubs.eventQueue.queued) == 1, "nothing was queued to run later"


def test_a_say_all_style_chain_advances_one_chunk_per_turn(filter_handler: SpeechFilter) -> None:
	"""The shape that broke: each callback speaks the next chunk, as say all does."""
	spoken: list[str] = []
	remaining = ["second", "third"]

	def next_line() -> None:
		if not remaining:
			return
		line = remaining.pop(0)
		spoken.append(line)
		filter_handler([nvda_stubs.StubCallbackCommand(next_line), line])

	spoken.append("first")
	filter_handler([nvda_stubs.StubCallbackCommand(next_line), "first"])
	nvda_stubs.eventQueue.pump()

	assert spoken == ["first", "second", "third"], (
		"the chain stopped early, which is exactly the live say-all symptom"
	)


def test_the_audible_callbacks_are_the_deliberate_exception(filter_handler: SpeechFilter) -> None:
	beep = nvda_stubs.StubBeepCommand()
	wave = nvda_stubs.StubWaveFileCommand()

	filter_handler([beep, wave, "and some words"])
	nvda_stubs.eventQueue.pump()

	assert not beep.beeped, "silent mode beeped"
	assert not wave.played, "silent mode played a wave file"


def test_the_words_are_still_suppressed_and_still_captured(clock: FakeClock) -> None:
	buffer = SpeechBuffer(clock, exact_finish=False)
	source = NvdaSilentSpeechSource()
	source.start(buffer, lambda: 0)
	handler = nvda_stubs.filter_speechSequence.handlers[0]

	returned = handler(["a heading", nvda_stubs.StubCallbackCommand(lambda: None)])

	assert returned == [], "something was handed on to the synth; the session is not silent"
	assert [entry[0] for entry in buffer.entries_since(1)[0]] == ["a heading"]


def test_a_failing_callback_does_not_escape_into_the_event_queue(filter_handler: SpeechFilter) -> None:
	def explode() -> None:
		raise RuntimeError("a say-all callback went wrong")

	filter_handler([nvda_stubs.StubCallbackCommand(explode)])
	nvda_stubs.eventQueue.pump()  # must not raise; it runs on NVDA's main loop

	assert any("callback failed" in message for message in nvda_stubs.log.messages), (
		"the failure was swallowed without a trace in NVDA's own log"
	)
