# Unit tests for domain/controllers/commands/session_context.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import pytest
from fakes.announcer import FakeAnnouncer
from fakes.clock import FakeClock
from fakes.gesture_resolver import FakeGestureResolver
from fakes.log_capture import FakeLogCapture
from fakes.transcript import FakeTranscript
from fakes.user_prompter import FakeUserPrompter
from nvdaMcpBridge.domain.controllers.commands.session_context import SessionContext
from nvdaMcpBridge.domain.controllers.teardown_reason import TeardownReason
from nvdaMcpBridge.domain.entities.silence_cap import (
	SilenceCap,
	SilenceCapAction,
	SilenceCapPolicy,
)
from support.context import RecordingClose, speech_with


def _bare(clock: FakeClock) -> SessionContext:
	return SessionContext(
		clock,
		FakeTranscript(),
		RecordingClose(),
		FakeAnnouncer(),
		FakeLogCapture(),
		FakeUserPrompter(),
		FakeGestureResolver(),
	)


def test_announce_to_human_speaks_and_notes_that_they_heard_it(clock: FakeClock) -> None:
	# The funnel: speaking and noting are ONE call, so a handler cannot make sound
	# the human hears and leave the silence cap counting a silence they were not in
	# -- which is what happened on 2026-08-20, from three handlers at once.
	announcer = FakeAnnouncer()
	ctx = SessionContext(
		clock,
		FakeTranscript(),
		RecordingClose(),
		announcer,
		FakeLogCapture(),
		FakeUserPrompter(),
		FakeGestureResolver(),
	)
	cap = SilenceCap(SilenceCapPolicy(enabled=True, warn_after=10.0, lift_after=20.0), clock.monotonic())
	ctx.silence_cap = cap
	clock.advance(9.0)
	ctx.announce_to_human("still working")
	clock.advance(9.0)

	assert announcer.announced == ["still working"]
	assert cap.check(clock.monotonic()) is SilenceCapAction.NONE, (
		"18 s of session, but only 9 s since the human was told: the window is the "
		"one that starts at the announcement"
	)


def test_announce_to_human_is_harmless_without_a_cap(clock: FakeClock) -> None:
	# Live mode, or an unattended machine: nothing is suppressed and there is no
	# cap to reset, and the announcement still has to go out.
	announcer = FakeAnnouncer()
	ctx = SessionContext(
		clock,
		FakeTranscript(),
		RecordingClose(),
		announcer,
		FakeLogCapture(),
		FakeUserPrompter(),
		FakeGestureResolver(),
	)
	ctx.announce_to_human("still working")
	assert announcer.announced == ["still working"]


def test_close_delegates_the_reason(clock: FakeClock) -> None:
	close = RecordingClose()
	ctx = SessionContext(
		clock,
		FakeTranscript(),
		close,
		FakeAnnouncer(),
		FakeLogCapture(),
		FakeUserPrompter(),
		FakeGestureResolver(),
	)
	ctx.close(TeardownReason.CLIENT_BYE)
	assert close.reasons == [TeardownReason.CLIENT_BYE]


def test_buffer_accessors_assert_before_hello_installs_them(clock: FakeClock) -> None:
	ctx = _bare(clock)
	with pytest.raises(AssertionError):
		_ = ctx.speech_buffer
	with pytest.raises(AssertionError):
		_ = ctx.braille_buffer
	with pytest.raises(AssertionError):
		_ = ctx.adapter_set


def test_accessors_return_what_was_installed(clock: FakeClock) -> None:
	ctx = _bare(clock)
	buffer = speech_with(clock)
	ctx.speech = buffer
	assert ctx.speech_buffer is buffer
