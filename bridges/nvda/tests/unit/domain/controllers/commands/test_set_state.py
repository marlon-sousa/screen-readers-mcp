# Unit tests for domain/controllers/commands/set_state.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import dataclasses

import pytest
from fakes.adapter_factory import FakeAdapterFactory
from fakes.clock import FakeClock
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.command_handler import CommandError
from nvdaMcpBridge.domain.controllers.commands.session_context import SessionContext
from nvdaMcpBridge.domain.controllers.commands.set_state import SetStateHandler
from nvdaMcpBridge.domain.ports.state_setter import StateSetError
from support.context import adapters_from, make_context, request


def _context(clock: FakeClock, browse_mode: str = "browse") -> tuple[FakeAdapterFactory, SessionContext]:
	factory = FakeAdapterFactory()
	factory.state_setter.browse_mode = browse_mode
	factory.state_inspector.reader_state = dataclasses.replace(
		factory.state_inspector.reader_state, browse_mode=browse_mode
	)
	return factory, make_context(clock, adapters=adapters_from(factory))


def test_a_difference_is_written_once_and_reported(clock: FakeClock) -> None:
	factory, ctx = _context(clock, browse_mode="focus")
	result = SetStateHandler().execute(ctx, request("setState", browseMode="browse"))
	assert isinstance(result, p.SetStateResult)
	assert result.changed == ["browseMode"]
	assert factory.state_setter.writes == ["browse"]


def test_already_there_writes_nothing_and_says_so(clock: FakeClock) -> None:
	factory, ctx = _context(clock, browse_mode="browse")
	result = SetStateHandler().execute(ctx, request("setState", browseMode="browse"))
	assert result.changed == []
	assert factory.state_setter.writes == []
	# The compare belongs to the port, so the handler dispatches regardless.
	assert factory.state_setter.calls == ["browse"]


def test_the_result_carries_the_state_after(clock: FakeClock) -> None:
	factory, ctx = _context(clock, browse_mode="focus")
	factory.state_inspector.reader_state = dataclasses.replace(
		factory.state_inspector.reader_state, browse_mode="browse"
	)
	result = SetStateHandler().execute(ctx, request("setState", browseMode="browse"))
	assert result.state.browseMode is p.BrowseMode.BROWSE


def test_none_is_refused_before_the_adapter_is_reached(clock: FakeClock) -> None:
	# "none" means the focus has no browsable document, which cannot be conjured.
	factory, ctx = _context(clock)
	with pytest.raises(CommandError) as caught:
		SetStateHandler().execute(ctx, request("setState", browseMode="none"))
	assert "cannot be set" in str(caught.value)
	assert factory.state_setter.calls == []


def test_a_non_browsable_focus_says_the_specific_reason(clock: FakeClock) -> None:
	factory, ctx = _context(clock)
	factory.state_setter.fail_with = "the focused object is not a browsable document"
	with pytest.raises(StateSetError) as caught:
		SetStateHandler().execute(ctx, request("setState", browseMode="focus"))
	assert "not a browsable document" in str(caught.value)


def test_an_absent_field_is_never_touched(clock: FakeClock) -> None:
	factory, ctx = _context(clock)
	result = SetStateHandler().execute(ctx, request("setState"))
	assert result.changed == []
	assert factory.state_setter.calls == []


def test_an_unsettable_field_is_refused_by_name(clock: FakeClock) -> None:
	_factory, ctx = _context(clock)
	with pytest.raises(CommandError) as caught:
		SetStateHandler().execute(ctx, request("setState", speechMode="off"))
	assert "speechMode cannot be set" in str(caught.value)
	assert "unable to hear their own machine" in str(caught.value)


def test_input_help_is_refused_with_its_own_reason(clock: FakeClock) -> None:
	_factory, ctx = _context(clock)
	with pytest.raises(CommandError) as caught:
		SetStateHandler().execute(ctx, request("setState", inputHelp=True))
	assert "disarm every gesture" in str(caught.value)


def test_mutates_reader_is_true() -> None:
	assert SetStateHandler.mutates_reader is True
