# Unit tests for domain/controllers/commands/get_braille.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# Braille takes the coordinate too (spec 0021): a display refresh is exactly the
# kind of thing an agent needs to line up against the log, and the entry shape is
# the same as speech's for the same reason.

from __future__ import annotations

from fakes.clock import FakeClock
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.get_braille import GetBrailleHandler
from support.context import braille_with, make_context, request


def test_get_braille_reads_since_index(clock: FakeClock) -> None:
	ctx = make_context(clock, braille=braille_with(clock, "find: x"))
	result = GetBrailleHandler().execute(ctx, request("getBraille", sinceIndex=0))
	assert isinstance(result, p.BrailleResult)
	assert [entry.text for entry in result.entries] == ["find: x"]
	assert result.fromIndex == 0


def test_each_entry_carries_its_index_and_journal_position(clock: FakeClock) -> None:
	ctx = make_context(
		clock,
		braille=braille_with(clock, "find: x", "find: xy", log_positions=[12, 30]),
	)
	result = GetBrailleHandler().execute(ctx, request("getBraille", sinceIndex=0))
	assert isinstance(result, p.BrailleResult)
	assert [(entry.index, entry.logPosition) for entry in result.entries] == [(1, 12), (2, 30)]


def test_each_entry_carries_the_wall_clock_it_was_emitted_at(clock: FakeClock) -> None:
	# Braille rides along with speech (spec 0028), same as it did for the journal
	# coordinate: it is the same IndexedBuffer and the same question.
	clock.advance(1_755_000_000)
	ctx = make_context(clock, braille=braille_with(clock, "one", "two"))
	result = GetBrailleHandler().execute(ctx, request("getBraille", sinceIndex=0))
	assert isinstance(result, p.BrailleResult)
	assert all(entry.emittedAt for entry in result.entries)
