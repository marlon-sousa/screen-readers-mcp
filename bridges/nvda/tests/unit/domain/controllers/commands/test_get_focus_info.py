# Unit tests for domain/controllers/commands/get_focus_info.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from fakes.adapter_factory import FakeAdapterFactory
from fakes.clock import FakeClock
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.get_focus_info import GetFocusInfoHandler
from nvdaMcpBridge.domain.ports.focus_inspector import FocusInfo
from support.context import adapters_from, make_context, request


def test_returns_focus_info_mapped_to_wire_names(clock: FakeClock) -> None:
	factory = FakeAdapterFactory()
	factory.focus_inspector.info = FocusInfo(
		name="OK Button",
		role="BUTTON",
		states=["FOCUSABLE", "FOCUSED"],
		value="OK",
		app_module="notepad",
	)
	ctx = make_context(clock, adapters=adapters_from(factory))
	result = GetFocusInfoHandler().execute(ctx, request("getFocusInfo"))
	assert isinstance(result, p.FocusInfoResult)
	assert result.name == "OK Button"
	assert result.role == "BUTTON"
	assert result.states == ["FOCUSABLE", "FOCUSED"]
	assert result.value == "OK"
	assert result.appModule == "notepad"


def test_null_focus_yields_empty_result(clock: FakeClock) -> None:
	factory = FakeAdapterFactory()
	factory.focus_inspector.info = FocusInfo(
		name="",
		role="",
		states=[],
		value=None,
		app_module=None,
	)
	ctx = make_context(clock, adapters=adapters_from(factory))
	result = GetFocusInfoHandler().execute(ctx, request("getFocusInfo"))
	assert result.name == ""
	assert result.role == ""
	assert result.states == []
	assert result.value is None
	assert result.appModule is None
