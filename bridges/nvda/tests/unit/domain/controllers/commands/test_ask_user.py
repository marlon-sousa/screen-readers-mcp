# Unit tests for domain/controllers/commands/ask_user.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import pytest
from fakes.adapter_factory import FakeAdapterFactory
from fakes.clock import FakeClock
from fakes.transcript import FakeTranscript
from fakes.user_prompter import FakeUserPrompter
from support.context import adapters_from, make_context, request

from nvdaMcpBridge.domain.controllers.commands.ask_user import AskUserHandler
from nvdaMcpBridge.domain.controllers.commands.command_handler import CommandError


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
	return ctx, factory, user_prompter, transcript


def test_ask_user_returns_a_ticket(clock: FakeClock) -> None:
	ctx, _, _, _ = _make_ctx(clock)
	result = AskUserHandler().execute(ctx, request("askUser", prompt="do the thing"))
	assert result.ticket
	assert len(result.ticket) == 12


def test_ask_user_suspends_speech(clock: FakeClock) -> None:
	ctx, factory, _, _ = _make_ctx(clock)
	AskUserHandler().execute(ctx, request("askUser", prompt="do the thing"))
	assert factory.speech_source.suspended == 1
	assert factory.speech_source.resumed == 0


def test_ask_user_presents_the_prompt(clock: FakeClock) -> None:
	ctx, _, prompter, _ = _make_ctx(clock)
	AskUserHandler().execute(ctx, request("askUser", prompt="plug in the display"))
	assert len(prompter.presented) == 1
	assert prompter.presented[0][0] == "plug in the display"


def test_ask_user_stores_prompt_on_context(clock: FakeClock) -> None:
	ctx, _, _, _ = _make_ctx(clock)
	AskUserHandler().execute(ctx, request("askUser", prompt="x"))
	prompt = ctx.get_outstanding_prompt()
	assert prompt is not None
	assert prompt.prompt == "x"
	assert not prompt.answered


def test_second_ask_user_is_an_error(clock: FakeClock) -> None:
	ctx, _, _, _ = _make_ctx(clock)
	AskUserHandler().execute(ctx, request("askUser", prompt="first"))
	with pytest.raises(CommandError, match="already outstanding"):
		AskUserHandler().execute(ctx, request("askUser", prompt="second"))


def test_ask_user_is_marked_mutates_reader() -> None:
	assert AskUserHandler.mutates_reader is True
