# Unit tests for domain/controllers/commands/type_text.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import pytest
from fakes.adapter_factory import FakeAdapterFactory
from fakes.clock import FakeClock
from fakes.transcript import FakeTranscript
from support.context import adapters_from, make_context, request

from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.type_text import TypeTextHandler
from nvdaMcpBridge.domain.ports.text_typer import TypingError


def _typed_events(transcript: FakeTranscript) -> list[tuple[object, ...]]:
	return [event for event in transcript.events if event[0] == "type"]


def test_types_the_text_and_logs_length_only(clock: FakeClock) -> None:
	factory = FakeAdapterFactory()
	transcript = FakeTranscript()
	ctx = make_context(clock, transcript=transcript, adapters=adapters_from(factory))

	result = TypeTextHandler().execute(ctx, request("typeText", text="www.blindtec.com.br"))

	assert isinstance(result, p.AckResult)
	assert factory.text_typer.typed == ["www.blindtec.com.br"]
	# The length is logged, never the text (spec 0019).
	assert _typed_events(transcript) == [("type", len("www.blindtec.com.br"))]
	for event in transcript.events:
		assert "www.blindtec.com.br" not in event


def test_mutates_reader_is_true() -> None:
	assert TypeTextHandler.mutates_reader is True


def test_typing_error_propagates(clock: FakeClock) -> None:
	factory = FakeAdapterFactory(type_fail_on=["bad"])
	transcript = FakeTranscript()
	ctx = make_context(clock, transcript=transcript, adapters=adapters_from(factory))

	with pytest.raises(TypingError):
		TypeTextHandler().execute(ctx, request("typeText", text="bad"))

	# Logged before injection, mirroring PressGestureHandler.
	assert _typed_events(transcript) == [("type", 3)]


def test_rejects_missing_text(clock: FakeClock) -> None:
	factory = FakeAdapterFactory()
	ctx = make_context(clock, adapters=adapters_from(factory))
	with pytest.raises(p.ValidationError):
		TypeTextHandler().execute(ctx, request("typeText"))
