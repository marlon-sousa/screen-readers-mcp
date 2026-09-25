# nvdaMcpBridge tests -- builders for command-handler tests.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from collections.abc import Callable, Sequence
from typing import TYPE_CHECKING

from fakes.announcer import FakeAnnouncer
from fakes.gesture_resolver import FakeGestureResolver
from fakes.log_capture import FakeLogCapture
from fakes.transcript import FakeTranscript
from fakes.user_prompter import FakeUserPrompter
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.session_context import SessionContext
from nvdaMcpBridge.domain.entities.braille_buffer import BrailleBuffer
from nvdaMcpBridge.domain.entities.speech_buffer import SpeechBuffer

if TYPE_CHECKING:
	from fakes.adapter_factory import FakeAdapterFactory
	from fakes.clock import FakeClock
	from nvdaMcpBridge.domain.controllers.teardown_reason import TeardownReason
	from nvdaMcpBridge.domain.ports.adapter_factory import AdapterSet


class RecordingClose:
	def __init__(self) -> None:
		self.reasons: list[TeardownReason] = []

	def __call__(self, reason: TeardownReason) -> None:
		self.reasons.append(reason)


def make_context(
	clock: FakeClock,
	*,
	transcript: FakeTranscript | None = None,
	speech: SpeechBuffer | None = None,
	braille: BrailleBuffer | None = None,
	adapters: AdapterSet | None = None,
	close: RecordingClose | None = None,
	announcer: FakeAnnouncer | None = None,
	log_capture: FakeLogCapture | None = None,
	user_prompter: FakeUserPrompter | None = None,
	gesture_resolver: FakeGestureResolver | None = None,
	teardown_requested: Callable[[], bool] | None = None,
) -> SessionContext:
	ctx = SessionContext(
		clock,
		transcript or FakeTranscript(),
		close or RecordingClose(),
		announcer or FakeAnnouncer(),
		log_capture or FakeLogCapture(),
		user_prompter or FakeUserPrompter(),
		gesture_resolver or FakeGestureResolver(),
		teardown_requested,
	)
	ctx.speech = speech
	ctx.braille = braille
	ctx.adapters = adapters
	return ctx


def speech_with(
	clock: FakeClock,
	*lines: str,
	exact_finish: bool = True,
	log_positions: Sequence[int] | None = None,
) -> SpeechBuffer:
	buffer = SpeechBuffer(clock, exact_finish=exact_finish)
	for index, line in enumerate(lines):
		buffer.append([line], log_positions[index] if log_positions else 0)
	if lines:
		buffer.notify_finished()
	return buffer


def braille_with(
	clock: FakeClock,
	*lines: str,
	log_positions: Sequence[int] | None = None,
) -> BrailleBuffer:
	buffer = BrailleBuffer(clock)
	for index, line in enumerate(lines):
		buffer.append(line, log_positions[index] if log_positions else 0)
	return buffer


def request(cmd: str, id: int = 1, **params: object) -> p.Request:
	return p.Request(id=id, cmd=cmd, params=dict(params))


def adapters_from(factory: FakeAdapterFactory) -> AdapterSet:
	return factory.build(p.CaptureMode.SILENT)
