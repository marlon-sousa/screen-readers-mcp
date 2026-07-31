# Unit tests for domain/controllers/commands/wait_for_user_reply.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import pytest
from fakes.adapter_factory import FakeAdapterFactory
from fakes.clock import FakeClock
from fakes.transcript import FakeTranscript
from fakes.user_prompter import FakeUserPrompter
from nvdaMcpBridge.domain.controllers.commands.command_handler import CommandError
from nvdaMcpBridge.domain.controllers.commands.wait_for_user_reply import (
	MAX_POLL_TIMEOUT,
	WaitForUserReplyHandler,
)
from nvdaMcpBridge.domain.entities.user_prompt import UserPrompt
from support.context import adapters_from, make_context, request


def _make_ctx(clock: FakeClock):
	factory = FakeAdapterFactory()
	adapters = adapters_from(factory)
	user_prompter = FakeUserPrompter()
	transcript = FakeTranscript()
	ctx = make_context(
		clock,
		adapters=adapters,
		user_prompter=user_prompter,
		transcript=transcript,
	)
	return ctx, factory, transcript


def test_poll_miss_returns_answered_false(clock: FakeClock) -> None:
	ctx, _, _ = _make_ctx(clock)
	prompt = UserPrompt("do the thing", clock)
	ctx.set_outstanding_prompt(prompt)
	# The clock's sleep advances instantly, and nothing answers, so this
	# returns answered=false at its timeout.
	result = WaitForUserReplyHandler().execute(
		ctx, request("waitForUserReply", ticket=prompt.ticket, timeout=0.0)
	)
	assert result.answered is False
	assert prompt.answered is False
	# Window is still open: the prompt was not cleared.
	assert ctx.get_outstanding_prompt() is prompt


def test_wrong_ticket_is_error(clock: FakeClock) -> None:
	ctx, _, _ = _make_ctx(clock)
	prompt = UserPrompt("do the thing", clock)
	ctx.set_outstanding_prompt(prompt)
	with pytest.raises(CommandError, match="no outstanding prompt"):
		WaitForUserReplyHandler().execute(
			ctx, request("waitForUserReply", ticket="bogus-ticket", timeout=0.0)
		)


def test_answered_resumes_speech_and_clears_prompt(clock: FakeClock) -> None:
	ctx, factory, _ = _make_ctx(clock)
	prompt = UserPrompt("do the thing", clock)
	ctx.set_outstanding_prompt(prompt)
	prompt.answer()
	result = WaitForUserReplyHandler().execute(
		ctx, request("waitForUserReply", ticket=prompt.ticket, timeout=0.0)
	)
	assert result.answered is True
	assert result.text == ""
	assert factory.speech_source.resumed == 1
	assert ctx.get_outstanding_prompt() is None


def test_expired_prompt_resumes_speech_and_returns_answered_false(
	clock: FakeClock,
) -> None:
	ctx, factory, _ = _make_ctx(clock)
	prompt = UserPrompt("do the thing", clock)
	ctx.set_outstanding_prompt(prompt)
	clock.advance(301.0)
	result = WaitForUserReplyHandler().execute(
		ctx, request("waitForUserReply", ticket=prompt.ticket, timeout=0.0)
	)
	assert result.answered is False
	assert factory.speech_source.resumed == 1
	assert ctx.get_outstanding_prompt() is None


def test_poll_timeout_is_clamped_below_the_inactivity_window(clock: FakeClock) -> None:
	# A poll may not block longer than MAX_POLL_TIMEOUT. The inactivity watchdog is
	# measured from DISPATCH and is deliberately not refreshed when a handler
	# returns (spec 0016), so a 300 s poll would answer the agent and then have the
	# session torn down under it. Clamping here protects every client, not only the
	# one whose tool schema says 110.
	ctx, _, transcript = _make_ctx(clock)
	prompt = UserPrompt("do the thing", clock)
	ctx.set_outstanding_prompt(prompt)

	started = clock.monotonic()
	result = WaitForUserReplyHandler().execute(
		ctx, request("waitForUserReply", ticket=prompt.ticket, timeout=300.0)
	)
	elapsed = clock.monotonic() - started

	assert result.answered is False
	# It waited the cap, not the 300 s asked for -- which also means it stopped
	# short of the window's own 300 s deadline, so the window is still open.
	assert elapsed == pytest.approx(MAX_POLL_TIMEOUT, abs=1.0)
	assert ctx.get_outstanding_prompt() is prompt
	assert any(event[0] == "note" and "clamped" in event[1] for event in transcript.events), (
		f"the clamp was not recorded in the transcript: {transcript.events}"
	)


def test_no_outstanding_prompt_is_error(clock: FakeClock) -> None:
	ctx, _, _ = _make_ctx(clock)
	with pytest.raises(CommandError, match="no outstanding prompt"):
		WaitForUserReplyHandler().execute(ctx, request("waitForUserReply", ticket="anything", timeout=0.0))
