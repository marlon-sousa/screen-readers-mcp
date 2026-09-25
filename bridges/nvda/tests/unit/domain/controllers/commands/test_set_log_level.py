# Unit tests for domain/controllers/commands/set_log_level.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import pytest
from fakes.announcer import FakeAnnouncer
from fakes.clock import FakeClock
from fakes.log_capture import FakeLogCapture
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.command_handler import CommandError
from nvdaMcpBridge.domain.controllers.commands.session_context import SessionContext
from nvdaMcpBridge.domain.controllers.commands.set_log_level import SetLogLevelHandler
from support.context import make_context, request


def _set_level(ctx: SessionContext, level: str) -> p.LogLevelResult:
	result = SetLogLevelHandler().execute(ctx, request("setLogLevel", level=level))
	assert isinstance(result, p.LogLevelResult)
	return result


def test_set_log_level_changes_the_level_and_reports_the_previous(clock: FakeClock) -> None:
	capture = FakeLogCapture()
	capture.start(p.LogLevel.INFO)
	ctx = make_context(clock, log_capture=capture)

	result = _set_level(ctx, "debug")

	assert result.level is p.LogLevel.DEBUG
	assert result.previous is p.LogLevel.INFO
	assert capture.current_level is p.LogLevel.DEBUG


def test_set_log_level_is_announced_to_the_tester(clock: FakeClock) -> None:
	announcer = FakeAnnouncer()
	capture = FakeLogCapture()
	capture.start(p.LogLevel.INFO)
	ctx = make_context(clock, log_capture=capture, announcer=announcer)

	_set_level(ctx, "io")

	assert announcer.announced == ["Log level io"]


def test_set_log_level_mutates_the_reader() -> None:
	assert SetLogLevelHandler.mutates_reader is True


@pytest.mark.parametrize("level", ["warning", "error"])
def test_filter_only_levels_cannot_be_set(clock: FakeClock, level: str) -> None:
	# Setting NVDA's own floor to either would silence warnings in the human's nvda.log.
	capture = FakeLogCapture()
	capture.start(p.LogLevel.INFO)
	ctx = make_context(clock, log_capture=capture)

	with pytest.raises(CommandError, match="cannot be set on the reader"):
		_set_level(ctx, level)

	assert capture.current_level is p.LogLevel.INFO
	assert ("set_level", p.LogLevel(level)) not in capture.events


@pytest.mark.parametrize("level", ["debug", "io", "debugwarning", "info"])
def test_every_settable_level_is_accepted(clock: FakeClock, level: str) -> None:
	capture = FakeLogCapture()
	capture.start(p.LogLevel.INFO)
	ctx = make_context(clock, log_capture=capture)

	assert _set_level(ctx, level).level is p.LogLevel(level)


def test_teardown_restores_the_level_the_session_started_from(clock: FakeClock) -> None:
	capture = FakeLogCapture()
	capture.start(p.LogLevel.INFO)
	ctx = make_context(clock, log_capture=capture)

	_set_level(ctx, "io")
	capture.stop()

	# Back to the untouched floor, which the fake models as NVDA's own default.
	assert capture.current_level is p.LogLevel.INFO
