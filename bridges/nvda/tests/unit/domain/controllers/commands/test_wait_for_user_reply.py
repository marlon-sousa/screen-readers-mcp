# Unit tests for domain/controllers/commands/wait_for_user_reply.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import pytest
from fakes.adapter_factory import FakeAdapterFactory
from fakes.clock import FakeClock
from fakes.transcript import FakeTranscript
from fakes.user_prompter import FakeUserPrompter
from support.context import adapters_from, make_context, request

from nvdaMcpBridge.domain.controllers.commands.command_handler import CommandError
from nvdaMcpBridge.domain.controllers.commands.wait_for_user_reply import (
    WaitForUserReplyHandler,
)
from nvdaMcpBridge.domain.entities.user_prompt import UserPrompt


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


def test_no_outstanding_prompt_is_error(clock: FakeClock) -> None:
    ctx, _, _ = _make_ctx(clock)
    with pytest.raises(CommandError, match="no outstanding prompt"):
        WaitForUserReplyHandler().execute(
            ctx, request("waitForUserReply", ticket="anything", timeout=0.0)
        )
