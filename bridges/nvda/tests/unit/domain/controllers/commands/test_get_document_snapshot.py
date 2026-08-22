# Unit tests for domain/controllers/commands/get_document_snapshot.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from fakes.adapter_factory import FakeAdapterFactory
from fakes.clock import FakeClock
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.get_document_snapshot import GetDocumentSnapshotHandler
from support.context import adapters_from, make_context, request

PAGE = ["heading level 1 BlindTec", "link Skip to content", "radio button checked Yes"]


def _factory(**kwargs: object) -> FakeAdapterFactory:
	factory = FakeAdapterFactory()
	factory.document_reader.lines = list(PAGE)
	factory.document_reader.title = "BlindTec"
	for key, value in kwargs.items():
		setattr(factory.document_reader, key, value)
	return factory


def test_a_bare_call_returns_the_whole_document(clock: FakeClock) -> None:
	# No parameters is the ordinary call, and it is unbounded: a snapshot
	# bounded by default would be incomplete by default (spec 0026).
	ctx = make_context(clock, adapters=adapters_from(_factory()))
	result = GetDocumentSnapshotHandler().execute(ctx, request("getDocumentSnapshot"))
	assert isinstance(result, p.DocumentSnapshotResult)
	assert result.hasDocument is True
	assert [line.text for line in result.lines] == PAGE
	assert (result.fromLine, result.toLine) == (0, 3)
	assert result.truncatedBy is p.TruncatedBy.NONE
	assert result.title == "BlindTec"


def test_the_roles_survive_into_the_result(clock: FakeClock) -> None:
	# What the maintainer asked for: the buffer as rendered, headings and radio
	# buttons and all. The handler must not strip or reshape any of it.
	ctx = make_context(clock, adapters=adapters_from(_factory()))
	result = GetDocumentSnapshotHandler().execute(ctx, request("getDocumentSnapshot"))
	assert "heading level 1" in result.lines[0].text
	assert "radio button checked" in result.lines[2].text


def test_no_document_is_a_false_and_not_an_error(clock: FakeClock) -> None:
	# A dialog, the desktop, a native app. Everything empty EXCEPT the stamp:
	# the bridge did look, at a time, and found nothing.
	clock.advance(1000.0)
	ctx = make_context(clock, adapters=adapters_from(_factory(has_document=False)))
	result = GetDocumentSnapshotHandler().execute(ctx, request("getDocumentSnapshot"))
	assert result.hasDocument is False
	assert result.lines == []
	assert result.title == ""
	assert (result.fromLine, result.toLine) == (0, 0)
	assert result.truncatedBy is p.TruncatedBy.NONE
	assert result.capturedAt != ""


def test_captured_at_comes_from_the_injected_clock(clock: FakeClock) -> None:
	# The one field that stops this result reading as a description of the page
	# rather than of the page at an instant, so it is asserted rather than
	# assumed.
	clock.advance(1000.0)
	ctx = make_context(clock, adapters=adapters_from(_factory()))
	result = GetDocumentSnapshotHandler().execute(ctx, request("getDocumentSnapshot"))
	from nvdaMcpBridge.domain.controllers.commands.wallclock import format_wallclock

	assert result.capturedAt == format_wallclock(clock.time())


def test_bounds_reach_the_snapshot_and_the_cause_is_reported(clock: FakeClock) -> None:
	factory = _factory()
	ctx = make_context(clock, adapters=adapters_from(factory))
	result = GetDocumentSnapshotHandler().execute(ctx, request("getDocumentSnapshot", maxLines=2))
	assert [line.text for line in result.lines] == PAGE[:2]
	assert result.truncatedBy is p.TruncatedBy.MAX_LINES
	# And the walk stopped: a bound the reader honours saves the render.
	assert factory.document_reader.offered == 3


def test_from_line_reaches_the_snapshot_with_absolute_ordinals(clock: FakeClock) -> None:
	ctx = make_context(clock, adapters=adapters_from(_factory()))
	result = GetDocumentSnapshotHandler().execute(ctx, request("getDocumentSnapshot", fromLine=1))
	assert [(line.line, line.text) for line in result.lines] == [(1, PAGE[1]), (2, PAGE[2])]
	assert (result.fromLine, result.toLine) == (1, 3)


def test_an_empty_document_is_not_a_missing_one(clock: FakeClock) -> None:
	# A page with nothing on it still HAS a document, and an agent must be able
	# to tell that from "you are not in a document at all".
	ctx = make_context(clock, adapters=adapters_from(_factory(lines=[])))
	result = GetDocumentSnapshotHandler().execute(ctx, request("getDocumentSnapshot"))
	assert result.hasDocument is True
	assert result.lines == []


def test_the_snapshot_observes_and_does_not_mutate() -> None:
	# Spec 0017: an observe-only session may read the page, because rendering
	# speaks nothing and moves no caret.
	assert GetDocumentSnapshotHandler.mutates_reader is False
