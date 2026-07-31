# Unit tests for domain/entities/user_prompt.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import pytest
from fakes.clock import FakeClock
from nvdaMcpBridge.domain.entities.user_prompt import PromptExpired, UserPrompt


def test_answer_sets_answered_flag(clock: FakeClock) -> None:
	prompt = UserPrompt("do the thing", clock)
	assert not prompt.answered
	prompt.answer()
	assert prompt.answered


def test_answer_is_idempotent(clock: FakeClock) -> None:
	prompt = UserPrompt("do the thing", clock)
	prompt.answer("first")
	prompt.answer("second")
	assert prompt.answered
	assert prompt.text == "first"


def test_wait_returns_true_when_already_answered(clock: FakeClock) -> None:
	prompt = UserPrompt("do the thing", clock)
	prompt.answer()
	assert prompt.wait(timeout=1.0) is True


def test_poll_miss_returns_false_window_still_open(clock: FakeClock) -> None:
	prompt = UserPrompt("do the thing", clock)
	# The clock sleeps during wait; advance past the poll timeout.
	clock.sleeps.clear()
	assert prompt.wait(timeout=0.0) is False


def test_wait_returns_true_after_answer(clock: FakeClock) -> None:
	prompt = UserPrompt("do the thing", clock)
	# Inject the answer as a side effect of the clock's sleep.
	original_sleep = clock.sleep

	def sleep_with_answer(seconds: float) -> None:
		original_sleep(seconds)
		if not prompt.answered:
			prompt.answer()

	clock.sleep = sleep_with_answer  # type: ignore[method-assign]
	assert prompt.wait(timeout=1.0) is True


def test_expired_prompt_raises_on_wait(clock: FakeClock) -> None:
	prompt = UserPrompt("do the thing", clock)
	# Advance the clock past the 300 s window.
	clock.advance(301.0)
	with pytest.raises(PromptExpired, match="deadline"):
		prompt.wait(timeout=1.0)


def test_expired_prompt_is_marked_cancelled(clock: FakeClock) -> None:
	prompt = UserPrompt("do the thing", clock)
	clock.advance(301.0)
	with pytest.raises(PromptExpired):
		prompt.wait(timeout=1.0)
	# Answering an expired prompt is a no-op.
	prompt.answer()
	assert not prompt.answered


def test_cancelled_prompt_raises_on_wait(clock: FakeClock) -> None:
	prompt = UserPrompt("do the thing", clock)
	prompt.cancel()
	with pytest.raises(PromptExpired, match="cancelled"):
		prompt.wait(timeout=1.0)


def test_each_prompt_has_a_unique_ticket(clock: FakeClock) -> None:
	a = UserPrompt("first", clock)
	b = UserPrompt("second", clock)
	assert a.ticket != b.ticket


def test_cancel_is_idempotent(clock: FakeClock) -> None:
	prompt = UserPrompt("do the thing", clock)
	prompt.cancel()
	prompt.cancel()  # does not raise
	with pytest.raises(PromptExpired):
		prompt.wait(timeout=0.0)
