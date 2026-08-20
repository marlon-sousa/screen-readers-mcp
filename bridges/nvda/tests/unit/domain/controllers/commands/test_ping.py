# Unit tests for domain/controllers/commands/ping.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from fakes.adapter_factory import FakeAdapterFactory
from fakes.clock import FakeClock
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.ping import PingHandler
from support.context import adapters_from, make_context, request


def test_ping_returns_ack(clock: FakeClock) -> None:
	result = PingHandler().execute(make_context(clock), request("ping"))
	assert isinstance(result, p.PingResult)
	assert result.ok is True


def test_ping_does_not_reset_inactivity() -> None:
	assert PingHandler.resets_inactivity is False


def test_ping_reports_the_suppression_state(clock: FakeClock) -> None:
	# This is how a silence-cap lift becomes discoverable by asking (spec 0032):
	# `status` makes its round trip with `ping`, so the fact rides on a probe that
	# was being sent anyway.
	factory = FakeAdapterFactory()
	ctx = make_context(clock, adapters=adapters_from(factory))
	assert PingHandler().execute(ctx, request("ping")).suppressing is True

	factory.speech_source.stop_suppressing()
	assert PingHandler().execute(ctx, request("ping")).suppressing is False


def test_ping_says_nothing_about_speech_before_hello(clock: FakeClock) -> None:
	# No adapters yet, so there is no honest answer -- and None is a different fact
	# from either boolean.
	assert PingHandler().execute(make_context(clock), request("ping")).suppressing is None
