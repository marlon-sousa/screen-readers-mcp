# Unit tests for domain/controllers/commands/get_state.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from fakes.adapter_factory import FakeAdapterFactory
from fakes.clock import FakeClock
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.get_state import GetStateHandler
from nvdaMcpBridge.domain.ports.state_inspector import ReaderState
from support.context import adapters_from, make_context, request


def test_returns_state_mapped_to_wire_names(clock: FakeClock) -> None:
	factory = FakeAdapterFactory()
	factory.state_inspector.reader_state = ReaderState(
		browse_mode="browse",
		speech_mode="talk",
		sleep_mode=False,
		input_help=False,
	)
	ctx = make_context(clock, adapters=adapters_from(factory))
	result = GetStateHandler().execute(ctx, request("getState"))
	assert isinstance(result, p.StateResult)
	assert result.browseMode == "browse"
	assert result.speechMode == "talk"
	assert result.sleepMode is False
	assert result.inputHelp is False


def test_identifies_focus_mode(clock: FakeClock) -> None:
	factory = FakeAdapterFactory()
	factory.state_inspector.reader_state = ReaderState(
		browse_mode="focus",
		speech_mode="talk",
		sleep_mode=False,
		input_help=False,
	)
	ctx = make_context(clock, adapters=adapters_from(factory))
	result = GetStateHandler().execute(ctx, request("getState"))
	assert result.browseMode == "focus"


def test_identifies_no_browse_document(clock: FakeClock) -> None:
	factory = FakeAdapterFactory()
	factory.state_inspector.reader_state = ReaderState(
		browse_mode="none",
		speech_mode="off",
		sleep_mode=True,
		input_help=True,
	)
	ctx = make_context(clock, adapters=adapters_from(factory))
	result = GetStateHandler().execute(ctx, request("getState"))
	assert result.browseMode == "none"
	assert result.speechMode == "off"
	assert result.sleepMode is True
	assert result.inputHelp is True
