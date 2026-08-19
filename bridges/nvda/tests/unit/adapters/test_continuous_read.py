# Unit tests for NvdaContinuousRead -- the tests the live run had to stand in for.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# Board entry 11.21. This file exists because the FIRST version of this adapter
# was wrong, shipped, and was caught only by driving a real say all on a real
# machine -- and the port's own unit tests all passed, because the fake answered
# honestly and the flaw was in what the real signal MEANS.
#
# That version called `SayAllHandler.isRunning()`, whose implementation is
# `bool(self._getActiveSayAll())` -- a weakref to the reader object, assigned when
# a read starts and never reset. It therefore reports "the reader object has not
# been garbage-collected", and `_Reader` inherits `garbageHandler.TrackedObject`,
# which is expressly about objects reclaimed by the CYCLIC collector rather than
# by refcounting. Live, the settle went on answering "not finished" after the
# document ended and after a keypress that stopped the read: a settle that never
# settles, which is worse than the imprecision it was fixing.
#
# So the state under test here is the one that broke it, and the one no real
# timing can hold still: a reader object that is PRESENT but STOPPED. NVDA's
# readers record that themselves, each nulling the field its own stop() guards on
# (`_TextReader.reader`, `_ObjectsReader.walker`), which is what this adapter now
# reads instead.

from __future__ import annotations

from collections.abc import Iterator

import pytest
from support import nvda_stubs

nvda_stubs.install()

from nvdaMcpBridge.adapters.nvda_continuous_read import NvdaContinuousRead


@pytest.fixture(autouse=True)
def clean_handler() -> Iterator[None]:
	"""The stub module is process-wide, exactly as NVDA's own would be."""
	yield
	nvda_stubs.reset()


def _install(reader: object | None) -> None:
	nvda_stubs.set_say_all_handler(nvda_stubs.StubSayAllHandler(reader))


def test_a_reader_part_way_through_is_in_progress() -> None:
	_install(nvda_stubs.StubTextReader())
	assert NvdaContinuousRead().in_progress() is True


def test_a_stopped_reader_is_not_in_progress_even_though_it_is_still_alive() -> None:
	# THE REGRESSION. The weakref still hands the object back -- it outlives the
	# read by however long collection takes -- so "is there an object?" says yes
	# while the read is over. Asking the reader instead is the whole fix.
	_install(nvda_stubs.StubTextReader(stopped=True))
	assert NvdaContinuousRead().in_progress() is False, (
		"a finished read reported as in progress; the settle would never settle"
	)


def test_object_say_all_is_read_through_its_own_field() -> None:
	# _ObjectsReader keeps its state in `walker`, not `reader`; an adapter that
	# knew only about text say all would report object say all as finished
	# throughout, which is the original bug in a narrower place.
	_install(nvda_stubs.StubObjectsReader())
	assert NvdaContinuousRead().in_progress() is True

	_install(nvda_stubs.StubObjectsReader(stopped=True))
	assert NvdaContinuousRead().in_progress() is False


def test_no_active_reader_at_all() -> None:
	_install(None)
	assert NvdaContinuousRead().in_progress() is False


def test_before_the_reader_has_initialised_its_handler() -> None:
	# A real window: the add-on's global plugin is built during NVDA startup, and
	# sayAll.SayAllHandler is None until sayAll.initialize() rebinds it.
	nvda_stubs.set_say_all_handler(None)
	assert NvdaContinuousRead().in_progress() is False


def test_the_handler_is_read_at_call_time_not_at_import_time() -> None:
	# The other silent trap. `SayAllHandler` is a MODULE ATTRIBUTE that
	# initialize() rebinds, so an adapter that imported the name by value would
	# hold None for the life of the process and never report a read -- no error,
	# no log, just a bridge quietly back to guessing. Import happened at the top
	# of this file, with the handler still None; installing one now must be seen.
	adapter = NvdaContinuousRead()
	assert adapter.in_progress() is False

	_install(nvda_stubs.StubTextReader())

	assert adapter.in_progress() is True, "the handler was captured by value at import"


def test_a_reader_of_an_unknown_shape_fails_closed() -> None:
	# If a future NVDA renames those fields, getattr finds neither and this says
	# "not running" -- the settle falls back to the heuristic it had before this
	# port existed. A rename must not be able to produce the hang.
	_install(object())
	assert NvdaContinuousRead().in_progress() is False


def test_a_raising_handler_is_logged_and_treated_as_not_running() -> None:
	class Exploding:
		def _getActiveSayAll(self) -> object:
			raise RuntimeError("NVDA changed underneath us")

	nvda_stubs.set_say_all_handler(Exploding())

	assert NvdaContinuousRead().in_progress() is False
	assert any("continuous-read state" in message for message in nvda_stubs.log.messages)
