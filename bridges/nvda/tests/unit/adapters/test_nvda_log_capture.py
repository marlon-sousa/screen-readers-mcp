# Unit tests for adapters/nvda_log_capture.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import logging
from typing import Any

import pytest
from support.nvda_stubs import install as _install_nvda_stubs
from support.nvda_stubs import log as _STUB_LOG

_install_nvda_stubs()

from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.adapters.nvda_log_capture import (
	JournalHandler,
	NvdaLogCapture,
)
from nvdaMcpBridge.domain.entities.log_journal import LogJournal


def _journal_handlers() -> list[logging.Handler]:
	"""Only our handlers: pytest attaches its own capture handlers alongside."""
	return [h for h in _STUB_LOG.root.handlers if isinstance(h, JournalHandler)]


@pytest.fixture
def capture() -> Any:
	_STUB_LOG.root.handlers.clear()
	_STUB_LOG.root.setLevel(logging.INFO)
	instance = NvdaLogCapture()
	yield instance
	instance.stop()
	_STUB_LOG.root.handlers.clear()
	_STUB_LOG.root.setLevel(logging.INFO)


def _emit(message: str = "hello", *, level: int = logging.INFO, codepath: str | None = None) -> None:
	extra = {"codepath": codepath} if codepath is not None else None
	_STUB_LOG.root.log(level, message, extra=extra)


def _text(capture: NvdaLogCapture, **kwargs: Any) -> str:
	return capture.slice(0, capture.position(), **kwargs)[0]


def test_logging_still_works_while_the_journal_is_attached(capture: NvdaLogCapture) -> None:
	# logging calls emit() unguarded, so any exception in it propagates into the NVDA line that logged.
	capture.start(None)

	_emit("NVDA carries on")

	assert capture.position() == 1


def test_a_record_that_cannot_be_rendered_is_dropped_not_raised() -> None:
	journal = LogJournal()
	handler = JournalHandler(journal)
	record = logging.LogRecord(
		"NVDA",
		logging.INFO,
		"somewhere.py",
		1,
		"two placeholders %s %s",
		("only-one-arg",),
		None,
	)

	handler.emit(record)

	assert journal.mark() == 0
	handler.emit(logging.LogRecord("NVDA", logging.INFO, "f.py", 1, "fine", None, None))
	assert journal.mark() == 1


def test_the_module_field_is_nvdas_codepath(capture: NvdaLogCapture) -> None:
	# NVDA has one logger, so record.name is always "NVDA"; the module is the `codepath` extra.
	capture.start(None)

	_emit("Speaking [Elements list]", codepath="speech.speech.speak")

	assert "speech.speech.speak" in _text(capture, fields=["module"])


def test_exclude_by_module_actually_drops_that_module(capture: NvdaLogCapture) -> None:
	capture.start(None)
	_emit("Speaking [Elements list]", codepath="speech.speech.speak")
	_emit("COMError on accName", codepath="IAccessibleHandler.getRole")

	text = _text(capture, exclude=["speech.speech.speak"])

	assert "COMError on accName" in text
	assert "Elements list" not in text


def test_a_record_without_codepath_falls_back_like_nvdas_formatter(
	capture: NvdaLogCapture,
) -> None:
	# A record with no codepath gets name.funcName, as NVDA's own Formatter makes.
	capture.start(None)

	_emit("from some library")

	module = _text(capture, fields=["module"])
	assert module.startswith("nvda-mcp-bridge-test-root.")


def test_the_timestamp_is_nvdas_own_local_time_shape(capture: NvdaLogCapture) -> None:
	# nvda.log renders local time only, as "09:17:40.724".
	capture.start(None)

	_emit("timed")

	stamp = _text(capture, fields=["time"]).strip("()")
	hours, minutes, rest = stamp.split(":")
	seconds, millis = rest.split(".")
	assert len(hours) == 2 and len(minutes) == 2 and len(seconds) == 2
	assert len(millis) == 3
	assert 0 <= int(hours) <= 23


def test_a_full_field_slice_reproduces_an_nvda_log_line(capture: NvdaLogCapture) -> None:
	capture.start(None)
	_emit("Input: kb(desktop):v", codepath="inputCore.InputManager.executeGesture")

	line = _text(capture, fields=["level", "module", "time", "thread", "thread_id", "message"])

	# LEVEL - codepath (time) - thread (id):\nmessage
	head, message = line.split(":\n")
	assert message == "Input: kb(desktop):v"
	assert head.startswith("INFO - inputCore.InputManager.executeGesture (")


def test_start_raises_the_floor_and_stop_restores_it(capture: NvdaLogCapture) -> None:
	_STUB_LOG.root.setLevel(logging.INFO)

	capture.start(p.LogLevel.DEBUG)
	assert _STUB_LOG.root.level == logging.DEBUG

	capture.stop()
	assert _STUB_LOG.root.level == logging.INFO


def test_stop_restores_what_the_session_started_from_not_the_last_set_level(
	capture: NvdaLogCapture,
) -> None:
	_STUB_LOG.root.setLevel(logging.INFO)
	capture.start(p.LogLevel.DEBUG)

	capture.set_level(p.LogLevel.IO)
	assert _STUB_LOG.root.level == 12

	capture.stop()
	assert _STUB_LOG.root.level == logging.INFO


def test_stop_is_safe_when_start_was_never_reached(capture: NvdaLogCapture) -> None:
	capture.stop()
	assert _journal_handlers() == []


def test_stop_detaches_the_handler_so_nvda_stops_paying_for_it(
	capture: NvdaLogCapture,
) -> None:
	capture.start(None)
	assert len(_journal_handlers()) == 1

	capture.stop()

	assert _journal_handlers() == []


def test_io_is_reported_as_io_not_debugwarning(capture: NvdaLogCapture) -> None:
	# NVDA's IO level is 12, between DEBUG (10) and DEBUGWARNING (15).
	_STUB_LOG.root.setLevel(12)

	capture.start(None)

	assert capture.current_level is p.LogLevel.IO


@pytest.mark.parametrize(
	("level_no", "expected"),
	[
		(logging.DEBUG, p.LogLevel.DEBUG),
		(12, p.LogLevel.IO),
		(15, p.LogLevel.DEBUGWARNING),
		(logging.INFO, p.LogLevel.INFO),
		(logging.WARNING, p.LogLevel.WARNING),
		(logging.ERROR, p.LogLevel.ERROR),
		(logging.NOTSET, p.LogLevel.DEBUG),  # emits everything: the most verbose
	],
)
def test_every_floor_maps_to_the_level_it_actually_is(
	capture: NvdaLogCapture, level_no: int, expected: p.LogLevel
) -> None:
	_STUB_LOG.root.setLevel(level_no)

	capture.start(None)

	assert capture.current_level is expected


def test_an_explicit_level_is_what_gets_reported(capture: NvdaLogCapture) -> None:
	capture.start(p.LogLevel.DEBUGWARNING)
	assert capture.current_level is p.LogLevel.DEBUGWARNING


def test_set_level_moves_the_floor_and_what_is_reported(capture: NvdaLogCapture) -> None:
	capture.start(p.LogLevel.INFO)

	capture.set_level(p.LogLevel.DEBUG)

	assert _STUB_LOG.root.level == logging.DEBUG
	assert capture.current_level is p.LogLevel.DEBUG


def test_records_below_the_floor_never_reach_the_journal(capture: NvdaLogCapture) -> None:
	capture.start(p.LogLevel.INFO)

	_emit("debug detail", level=logging.DEBUG)

	assert capture.position() == 0

	capture.set_level(p.LogLevel.DEBUG)
	_emit("debug detail after raising", level=logging.DEBUG)

	assert "debug detail after raising" in _text(capture)
	assert "debug detail" in _text(capture)


def test_start_clears_the_previous_sessions_records(capture: NvdaLogCapture) -> None:
	capture.start(None)
	_emit("from the old session")
	capture.stop()

	capture.start(None)

	assert capture.position() == 0
	assert "from the old session" not in _text(capture)
