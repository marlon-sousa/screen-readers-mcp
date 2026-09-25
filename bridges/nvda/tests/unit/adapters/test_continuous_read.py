# Unit tests for NvdaContinuousRead -- the tests the live run had to stand in for.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# A stopped reader stays alive after the read ends; see StubSayAllHandler in tests/support/nvda_stubs.py.

from __future__ import annotations

from collections.abc import Iterator

import pytest
from support import nvda_stubs

nvda_stubs.install()

from nvdaMcpBridge.adapters.nvda_continuous_read import NvdaContinuousRead


@pytest.fixture(autouse=True)
def clean_handler() -> Iterator[None]:
	yield
	nvda_stubs.reset()


def _install(reader: object | None) -> None:
	nvda_stubs.set_say_all_handler(nvda_stubs.StubSayAllHandler(reader))


def test_a_reader_part_way_through_is_in_progress() -> None:
	_install(nvda_stubs.StubTextReader())
	assert NvdaContinuousRead().in_progress() is True


def test_a_stopped_reader_is_not_in_progress_even_though_it_is_still_alive() -> None:
	_install(nvda_stubs.StubTextReader(stopped=True))
	assert NvdaContinuousRead().in_progress() is False, (
		"a finished read reported as in progress; the settle would never settle"
	)


def test_object_say_all_is_read_through_its_own_field() -> None:
	_install(nvda_stubs.StubObjectsReader())
	assert NvdaContinuousRead().in_progress() is True

	_install(nvda_stubs.StubObjectsReader(stopped=True))
	assert NvdaContinuousRead().in_progress() is False


def test_no_active_reader_at_all() -> None:
	_install(None)
	assert NvdaContinuousRead().in_progress() is False


def test_before_the_reader_has_initialised_its_handler() -> None:
	# sayAll.SayAllHandler is None until sayAll.initialize() rebinds it during NVDA startup.
	nvda_stubs.set_say_all_handler(None)
	assert NvdaContinuousRead().in_progress() is False


def test_the_handler_is_read_at_call_time_not_at_import_time() -> None:
	# SayAllHandler is a module attribute initialize() rebinds, so importing it by value would hold None.
	adapter = NvdaContinuousRead()
	assert adapter.in_progress() is False

	_install(nvda_stubs.StubTextReader())

	assert adapter.in_progress() is True, "the handler was captured by value at import"


def test_a_reader_of_an_unknown_shape_fails_closed() -> None:
	# A renamed field must fall back to the heuristic, never hang the settle.
	_install(object())
	assert NvdaContinuousRead().in_progress() is False


def test_a_raising_handler_is_logged_and_treated_as_not_running() -> None:
	class Exploding:
		def _getActiveSayAll(self) -> object:
			raise RuntimeError("NVDA changed underneath us")

	nvda_stubs.set_say_all_handler(Exploding())

	assert NvdaContinuousRead().in_progress() is False
	assert any("continuous-read state" in message for message in nvda_stubs.log.messages)
