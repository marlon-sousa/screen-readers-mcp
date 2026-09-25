# Unit tests for domain/controllers/session.py, the lifecycle and dispatcher.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import threading
import time
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

import pytest
from fakes.adapter_factory import FakeAdapterFactory
from fakes.announcer import FakeAnnouncer
from fakes.clock import FakeClock
from fakes.command_handler import FakeCommandHandler
from fakes.config_accessor import FakeConfigAccessor
from fakes.gesture_resolver import FakeGestureResolver
from fakes.log_capture import FakeLogCapture
from fakes.message_channel import FakeChannel
from fakes.script import TIMEOUT_EVENT
from fakes.session_signals import FakeSessionSignals
from fakes.transcript import FakeTranscript
from fakes.user_prompter import FakeUserPrompter
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.adapters.real_clock import RealClock
from nvdaMcpBridge.domain.controllers.commands.command_handler import CommandError, CommandHandler
from nvdaMcpBridge.domain.controllers.commands.registry import NVDA_CAPABILITIES, build_command_registry
from nvdaMcpBridge.domain.controllers.commands.wait_for_log import WaitForLogHandler
from nvdaMcpBridge.domain.controllers.session import (
	MAX_COMMAND_WINDOWS,
	Session,
	SessionConfig,
	TeardownReason,
)
from nvdaMcpBridge.domain.entities.silence_cap import ATTENDED_DEFAULT, SilenceCapPolicy
from nvdaMcpBridge.domain.entities.user_prompt import PromptExpired, UserPrompt
from nvdaMcpBridge.domain.ports.announcer import SilenceNotice


def hello(
	mode: str = "silent",
	*,
	version: int = p.PROTOCOL_VERSION,
	id: int = 1,
	persona: str | None = None,
) -> dict[str, Any]:
	params: dict[str, Any] = {"mode": mode, "protocolVersion": version}
	if persona is not None:
		params["persona"] = persona
	return {"id": id, "cmd": "hello", "params": params}


def command(cmd: str, id: int, **params: Any) -> dict[str, Any]:
	return {"id": id, "cmd": cmd, "params": params}


@dataclass
class Run:
	session: Session
	channel: FakeChannel
	transcript: FakeTranscript
	factory: FakeAdapterFactory
	clock: FakeClock
	signals: FakeSessionSignals
	log_capture: FakeLogCapture
	announcer: FakeAnnouncer

	def responses(self) -> list[dict[str, Any]]:
		return self.channel.responses()

	def closed_with(self, reason: TeardownReason) -> bool:
		return ("session_closed", reason.value) in self.transcript.events


def run_session(
	events: list[Any],
	*,
	clock: FakeClock | None = None,
	factory: FakeAdapterFactory | None = None,
	transcript: FakeTranscript | None = None,
	registry: Mapping[str, CommandHandler] | None = None,
	signals: FakeSessionSignals | None = None,
	announcer: FakeAnnouncer | None = None,
	log_capture: FakeLogCapture | None = None,
	user_prompter: FakeUserPrompter | None = None,
	on_empty: str = "closed",
	timeout_advance: float = 5.0,
	nvda_version: str = "2026.1.0",
	heartbeat_timeout: float = 30.0,
	inactivity_timeout: float = 120.0,
	silence_cap: SilenceCapPolicy | None = None,
	attended: bool = True,
	start: bool = True,
) -> Run:
	clock = clock or FakeClock()
	factory = factory or FakeAdapterFactory()
	transcript = transcript or FakeTranscript()
	signals = signals or FakeSessionSignals()
	announcer = announcer or FakeAnnouncer()
	log_capture = log_capture or FakeLogCapture()
	user_prompter = user_prompter or FakeUserPrompter()
	if registry is None:
		registry = build_command_registry(factory, nvda_version)
	channel = FakeChannel(events, clock=clock, timeout_advance=timeout_advance, on_empty=on_empty)
	config = SessionConfig(
		nvda_version=nvda_version,
		heartbeat_timeout=heartbeat_timeout,
		inactivity_timeout=inactivity_timeout,
		silence_cap=silence_cap if silence_cap is not None else ATTENDED_DEFAULT,
		attended=attended,
	)
	session = Session(
		channel,
		transcript,
		clock,
		config,
		registry,
		signals,
		announcer,
		log_capture,
		user_prompter,
		FakeGestureResolver(),
	)
	if start:
		session.run()
	return Run(
		session=session,
		channel=channel,
		transcript=transcript,
		factory=factory,
		clock=clock,
		signals=signals,
		log_capture=log_capture,
		announcer=announcer,
	)


def _result(response: dict[str, Any]) -> dict[str, Any]:
	assert response["error"] is None, f"expected a result, got error {response['error']!r}"
	return response["result"]


def _error(response: dict[str, Any]) -> str:
	assert response["error"] is not None, f"expected an error, got result {response['result']!r}"
	return response["error"]["message"]


def _fake_registry(**handlers: CommandHandler) -> dict[str, CommandHandler]:
	"""A registry with a stand-in hello plus whatever fake handlers a mechanics test wants."""
	registry: dict[str, CommandHandler] = {
		p.Command.HELLO: FakeCommandHandler(available_before_hello=True, marks_log=False)
	}
	registry.update(handlers)
	return registry


def test_silent_hello_establishes_and_reports() -> None:
	run = run_session([hello("silent")])
	assert run.factory.built_mode is p.CaptureMode.SILENT
	assert run.signals.started == 1
	result = _result(run.responses()[0])
	assert result["mode"] == "silent"
	assert result["synth"] == "espeak"
	assert result["reader"] == {"name": "nvda", "version": "2026.1.0"}
	assert result["capabilities"] == [c.value for c in NVDA_CAPABILITIES]
	assert result["logPath"] == run.transcript.path


def test_the_start_cue_is_given_the_declared_persona() -> None:
	run = run_session([hello("silent", persona="validator")])
	assert run.signals.started == 1
	assert run.signals.personas == ["validator"]


def test_the_start_cue_says_nothing_when_no_persona_was_declared() -> None:
	run = run_session([hello("silent")])
	assert run.signals.personas == [""]


def test_a_failing_start_cue_leaves_the_session_established() -> None:

	class ExplodingSignals(FakeSessionSignals):
		def session_started(self, persona: str) -> None:
			super().session_started(persona)
			raise RuntimeError("no audio device")

	signals = ExplodingSignals()
	run = run_session([hello("silent", persona="user"), command("ping", id=2)], signals=signals)

	assert signals.personas == ["user"]
	assert _result(run.responses()[1]) == {"ok": True, "suppressing": True}


def test_live_hello_establishes() -> None:
	run = run_session([hello("live")])
	assert run.factory.built_mode is p.CaptureMode.LIVE
	assert run.signals.started == 1
	assert _result(run.responses()[0])["mode"] == "live"


def test_version_mismatch_errors_and_never_builds() -> None:
	run = run_session([hello(version=p.PROTOCOL_VERSION + 1)])
	message = _error(run.responses()[0])
	assert str(p.PROTOCOL_VERSION) in message and str(p.PROTOCOL_VERSION + 1) in message
	assert run.factory.built_mode is None
	assert run.closed_with(TeardownReason.HANDSHAKE_FAILED)
	assert run.channel.closed is True


def test_first_message_not_hello_fails_handshake() -> None:
	run = run_session([command("ping", 1)])
	assert "expected hello" in _error(run.responses()[0])
	assert run.closed_with(TeardownReason.HANDSHAKE_FAILED)


def test_unreadable_first_line_fails_handshake_without_reply() -> None:
	run = run_session([p.ValidationError("bad line")])
	assert run.responses() == []
	assert run.closed_with(TeardownReason.HANDSHAKE_FAILED)


def test_bad_hello_params_fail_handshake() -> None:
	run = run_session([command("hello", 1, mode="bogus", protocolVersion=p.PROTOCOL_VERSION)])
	assert run.closed_with(TeardownReason.HANDSHAKE_FAILED)
	assert run.responses()[0]["error"] is not None


def test_silence_before_hello_times_out() -> None:
	run = run_session([], on_empty="timeout", timeout_advance=5.0, heartbeat_timeout=30.0)
	assert run.responses() == []
	assert run.closed_with(TeardownReason.HANDSHAKE_FAILED)


def test_heartbeat_fires_when_no_message_arrives() -> None:
	run = run_session([hello()], on_empty="timeout", timeout_advance=5.0, heartbeat_timeout=30.0)
	assert run.closed_with(TeardownReason.HEARTBEAT_TIMEOUT)


def test_handler_blocking_past_heartbeat_window_does_not_end_session() -> None:
	# A handler blocking past the heartbeat window is our silence, not the peer's, so the heartbeat
	# is refreshed after dispatch too.
	clock = FakeClock()

	def long_running(ctx: object, request: object) -> p.AckResult:
		clock.advance(35.0)
		return p.AckResult()

	handler = FakeCommandHandler()
	handler.execute = long_running  # type: ignore[method-assign]
	registry = _fake_registry(ping=handler)

	run = run_session(
		[hello(), command("ping", 2), command("ping", 3)],
		registry=registry,
		clock=clock,
		heartbeat_timeout=30.0,
	)
	assert not run.closed_with(TeardownReason.HEARTBEAT_TIMEOUT)
	assert _result(run.responses()[1]) == {"ok": True}
	assert _result(run.responses()[2]) == {"ok": True}


def test_a_long_wait_for_log_does_not_trip_the_watchdogs() -> None:
	clock = FakeClock()
	registry = _fake_registry(
		waitForLog=WaitForLogHandler(),
		ping=FakeCommandHandler(resets_inactivity=False),
	)
	run = run_session(
		[hello(), command("waitForLog", 2, timeout=60.0, minLevel="error"), command("ping", 3)],
		registry=registry,
		clock=clock,
		log_capture=FakeLogCapture(),
		heartbeat_timeout=30.0,
	)

	assert clock.monotonic() >= 60.0, "the wait did not actually run its timeout"
	assert not run.closed_with(TeardownReason.HEARTBEAT_TIMEOUT)
	assert _result(run.responses()[1])["found"] is False
	assert _result(run.responses()[2]) == {"ok": True}


def test_pings_hold_the_heartbeat_but_not_inactivity() -> None:
	events: list[Any] = [hello()]
	for i in range(12):
		events.append(command("ping", 100 + i))
		events.append(TIMEOUT_EVENT)
	run = run_session(
		events,
		on_empty="timeout",
		timeout_advance=10.0,
		heartbeat_timeout=30.0,
		inactivity_timeout=120.0,
	)
	assert run.closed_with(TeardownReason.INACTIVITY_TIMEOUT)


# Each teardown step is guarded, so a raise in one never skips the channel close or the end cue.


def test_teardown_stops_capture_even_when_the_transcript_raises_on_close() -> None:
	transcript = FakeTranscript(fail_on={"session_closed"})
	run = run_session([hello("silent")], transcript=transcript)
	assert run.factory.speech_source.stopped == 1
	assert run.channel.closed is True


def test_teardown_finishes_even_when_a_source_stop_raises() -> None:
	factory = FakeAdapterFactory()
	factory.speech_source.fail_stop = True
	run = run_session([hello("silent")], factory=factory)
	assert factory.braille_source.stopped == 1
	assert run.signals.ended == 1
	assert run.channel.closed is True


def test_teardown_is_idempotent_when_called_twice() -> None:
	run = run_session([hello("silent")])
	run.session._teardown()  # type: ignore[attr-defined]
	assert run.factory.speech_source.stopped == 1
	assert run.signals.ended == 1
	assert run.log_capture.events.count(("stop",)) == 1


def test_teardown_stops_log_capture_even_when_it_raises_on_stop() -> None:
	log_capture = FakeLogCapture(fail_on={"stop"})
	run = run_session([hello("silent")], log_capture=log_capture)
	assert run.factory.speech_source.stopped == 1
	assert run.signals.ended == 1
	assert run.channel.closed is True


def test_teardown_with_an_open_window_leaves_the_tester_audible() -> None:
	# Teardown must not call resume(): it re-registers the suppression filter, and a raising stop()
	# after it would strand the tester mute.
	prompter = FakeUserPrompter()
	run = run_session(
		[hello("silent"), command("askUser", 2, prompt="plug in the display")],
		user_prompter=prompter,
	)
	ticket = _result(run.responses()[1])["ticket"]

	assert run.factory.speech_source.suspended == 1, "askUser did not suspend suppression"
	assert run.factory.speech_source.resumed == 0, "teardown re-suppressed a dying session"
	assert run.factory.speech_source.stopped == 1
	assert prompter.cancelled == [ticket]


def test_log_capture_stop_runs_even_when_hello_never_ran() -> None:
	run = run_session([command("ping", 1)])
	assert run.log_capture.events == [("stop",)]


def test_unknown_command_errors_without_killing_the_session() -> None:
	registry = _fake_registry(ping=FakeCommandHandler(resets_inactivity=False))
	run = run_session([hello(), command("frobnicate", 2), command("ping", 3)], registry=registry)
	assert "unknown command" in _error(run.responses()[1])
	assert _result(run.responses()[2]) == {"ok": True}


def test_a_handler_fault_becomes_an_error_and_the_session_continues() -> None:
	registry = _fake_registry(
		boom=FakeCommandHandler(error=RuntimeError("kaboom")),
		ping=FakeCommandHandler(resets_inactivity=False),
	)
	run = run_session([hello(), command("boom", 2), command("ping", 3)], registry=registry)
	assert "kaboom" in _error(run.responses()[1])
	assert _result(run.responses()[2]) == {"ok": True}


def test_a_command_error_becomes_an_error_and_the_session_continues() -> None:
	registry = _fake_registry(
		nope=FakeCommandHandler(error=CommandError("not yet")),
		ping=FakeCommandHandler(resets_inactivity=False),
	)
	run = run_session([hello(), command("nope", 2), command("ping", 3)], registry=registry)
	assert "not yet" in _error(run.responses()[1])
	assert _result(run.responses()[2]) == {"ok": True}


def test_duplicate_hello_errors_without_killing_the_session() -> None:
	registry = _fake_registry(ping=FakeCommandHandler(resets_inactivity=False))
	run = run_session([hello(id=1), hello(id=2), command("ping", 3)], registry=registry)
	assert _error(run.responses()[1]) == "session already established"
	assert _result(run.responses()[2]) == {"ok": True}


def test_garbage_with_an_id_gets_an_error_and_the_session_continues() -> None:
	registry = _fake_registry(ping=FakeCommandHandler(resets_inactivity=False))
	run = run_session([hello(), {"id": 5, "cmd": 123}, command("ping", 6)], registry=registry)
	responses = run.responses()
	assert responses[1]["id"] == 5 and responses[1]["error"] is not None
	assert _result(responses[2]) == {"ok": True}


def test_unreadable_message_mid_session_is_noted_and_survives() -> None:
	registry = _fake_registry(ping=FakeCommandHandler(resets_inactivity=False))
	run = run_session([hello(), p.ValidationError("boom"), command("ping", 3)], registry=registry)
	assert any(event[0] == "note" for event in run.transcript.events)
	# The unreadable line draws no reply, so the ping ack is the second response.
	assert _result(run.responses()[1]) == {"ok": True}


# A span runs from its command's dispatch to the next marking command's start, or to the journal's
# current position for the open one.


def _windows(run: Run) -> list[tuple[int, int, p.LogLevel]]:
	return run.session.session_context.command_windows


class _SpanReader(FakeCommandHandler):
	"""A non-marking handler that snapshots spans from inside the session; teardown resets the journal."""

	def __init__(self) -> None:
		super().__init__(marks_log=False, on_execute=self._snapshot)
		self.spans: list[tuple[int, int, int, p.LogLevel]] = []

	def _snapshot(self, ctx: Any) -> None:
		self.spans = ctx.command_windows_for(-1, MAX_COMMAND_WINDOWS)


READ_SPANS = 99


def _feeder(*messages: str) -> Any:
	"""An on_execute that logs *messages* while the command is running."""

	def feed(ctx: Any) -> None:
		for message in messages:
			ctx.log_capture.feed(message)

	return feed


def test_a_command_gets_a_span_holding_what_it_logged() -> None:
	reader = _SpanReader()
	registry = _fake_registry(
		work=FakeCommandHandler(on_execute=_feeder("during the command")),
		spans=reader,
	)
	run_session(
		[hello(), command("work", 2), command("spans", READ_SPANS)],
		registry=registry,
		log_capture=FakeLogCapture(),
	)

	assert len(reader.spans) == 1
	command_id, start, end, _level = reader.spans[0]
	assert command_id == 2
	assert end - start == 1


def test_spans_are_contiguous_with_no_gaps() -> None:
	reader = _SpanReader()
	registry = _fake_registry(
		first=FakeCommandHandler(on_execute=_feeder("a", "b")),
		second=FakeCommandHandler(on_execute=_feeder("c")),
		spans=reader,
	)
	run_session(
		[hello(), command("first", 2), command("second", 3), command("spans", READ_SPANS)],
		registry=registry,
		log_capture=FakeLogCapture(),
	)

	spans = reader.spans
	assert [s[0] for s in spans] == [2, 3]
	assert spans[0][1:3] == (0, 2)
	assert spans[1][1:3] == (2, 3)
	assert spans[0][2] == spans[1][1], "a record fell between two spans"


def test_a_span_extends_to_the_next_marking_command() -> None:
	# A non-marking command's records belong to the command last dispatched.
	reader = _SpanReader()
	registry = _fake_registry(
		work=FakeCommandHandler(on_execute=_feeder("inside the command")),
		peek=FakeCommandHandler(marks_log=False, on_execute=_feeder("what it caused, late")),
		later=FakeCommandHandler(on_execute=_feeder("the next command")),
		spans=reader,
	)
	run_session(
		[
			hello(),
			command("work", 2),
			command("peek", 3),
			command("later", 4),
			command("spans", READ_SPANS),
		],
		registry=registry,
		log_capture=FakeLogCapture(),
	)

	spans = reader.spans
	assert [s[0] for s in spans] == [2, 4]
	assert spans[0][1:3] == (0, 2), "the late record was not attributed to command 2"
	assert spans[1][1:3] == (2, 3)


def test_a_failed_command_still_gets_its_span() -> None:
	reader = _SpanReader()
	registry = _fake_registry(
		boom=FakeCommandHandler(on_execute=_feeder("the interesting line"), error=RuntimeError("kaboom")),
		spans=reader,
	)
	run = run_session(
		[hello(), command("boom", 2), command("spans", READ_SPANS)],
		registry=registry,
		log_capture=FakeLogCapture(),
	)

	assert "kaboom" in _error(run.responses()[1])
	assert [s[0] for s in reader.spans] == [2]
	assert reader.spans[0][2] - reader.spans[0][1] == 1


def test_a_command_error_also_gets_its_span() -> None:
	capture = FakeLogCapture()
	registry = _fake_registry(
		nope=FakeCommandHandler(on_execute=_feeder("why it failed"), error=CommandError("no")),
	)
	run = run_session([hello(), command("nope", 2)], registry=registry, log_capture=capture)

	assert [w[0] for w in _windows(run)] == [2]


def test_a_handler_that_does_not_mark_gets_no_span() -> None:
	capture = FakeLogCapture()
	registry = _fake_registry(
		peek=FakeCommandHandler(marks_log=False),
		work=FakeCommandHandler(),
	)
	run = run_session(
		[hello(), command("work", 2), command("peek", 3)],
		registry=registry,
		log_capture=capture,
	)

	assert [w[0] for w in _windows(run)] == [2]


def test_hello_does_not_mark_its_own_span() -> None:
	run = run_session([hello()])
	assert _windows(run) == []


def test_the_window_records_the_level_in_force_when_it_was_taken() -> None:
	capture = FakeLogCapture()
	registry = _fake_registry(work=FakeCommandHandler())
	run = run_session(
		[
			{
				"id": 1,
				"cmd": "hello",
				"params": {"mode": "silent", "protocolVersion": p.PROTOCOL_VERSION, "logLevel": "debug"},
			},
			command("work", 2),
		],
		registry=registry,
		log_capture=capture,
	)

	assert _windows(run)[0][2] is capture.current_level


def _logs_speaks_and_logs(factory: FakeAdapterFactory, spoken: str, brailled: str) -> Any:
	"""An on_execute that logs, captures speech and braille, then logs again."""

	def run(ctx: Any) -> None:
		ctx.log_capture.feed("what the command started doing")
		factory.speech_source.emit(spoken)
		factory.braille_source.emit(brailled)
		ctx.log_capture.feed("what it did next")

	return run


def test_speech_and_braille_carry_a_position_inside_their_commands_span() -> None:
	factory = FakeAdapterFactory()
	reader = _SpanReader()
	registry = dict(build_command_registry(factory, "2026.1.0"))
	registry["work"] = FakeCommandHandler(on_execute=_logs_speaks_and_logs(factory, "Elements list", "elem"))
	registry["spans"] = reader
	run = run_session(
		[
			hello(),
			command("work", 2),
			command("spans", READ_SPANS),
			command("getSpeech", 3, sinceIndex=0),
			command("getBraille", 4, sinceIndex=0),
		],
		registry=registry,
		factory=factory,
		log_capture=FakeLogCapture(),
	)

	assert [s[0] for s in reader.spans] == [2]
	_command_id, start, end, _level = reader.spans[0]

	speech = _result(run.responses()[3])["entries"]
	braille = _result(run.responses()[4])["entries"]
	assert speech and braille, "nothing was captured, so the coordinates prove nothing"
	for entry in (*speech, *braille):
		assert start <= entry["logPosition"] < end, (
			f"{entry['text']!r} is stamped at {entry['logPosition']}, outside its "
			f"command's span [{start}, {end})"
		)


def test_only_the_last_fifty_windows_are_kept() -> None:
	capture = FakeLogCapture()
	registry = _fake_registry(work=FakeCommandHandler())
	events: list[Any] = [hello()]
	events.extend(command("work", index) for index in range(2, 2 + MAX_COMMAND_WINDOWS + 10))
	run = run_session(events, registry=registry, log_capture=capture)

	windows = _windows(run)
	assert len(windows) == MAX_COMMAND_WINDOWS
	assert windows[-1][0] == 1 + MAX_COMMAND_WINDOWS + 10


def test_a_journal_that_cannot_be_read_costs_the_window_not_the_command() -> None:
	class BrokenCapture(FakeLogCapture):
		def position(self) -> int:
			raise RuntimeError("journal is gone")

	registry = _fake_registry(work=FakeCommandHandler())
	run = run_session([hello(), command("work", 2)], registry=registry, log_capture=BrokenCapture())

	assert _result(run.responses()[1]) == {"ok": True}
	assert _windows(run) == []


def test_bye_acks_then_tears_down() -> None:
	run = run_session([hello(), command("bye", 2)])
	assert _result(run.responses()[1]) == {"ok": True}
	assert run.closed_with(TeardownReason.CLIENT_BYE)
	assert run.channel.closed is True


def test_channel_close_tears_down() -> None:
	run = run_session([hello()])
	assert run.closed_with(TeardownReason.CHANNEL_CLOSED)


def test_gesture_error_becomes_an_error_and_the_session_survives() -> None:
	factory = FakeAdapterFactory(reject=["bad"])
	run = run_session(
		[hello(), command("pressGesture", 2, gestures=["bad"]), command("ping", 3)],
		factory=factory,
	)
	assert "bad" in _error(run.responses()[1])
	assert _result(run.responses()[2]) == {"ok": True, "suppressing": True}


def test_request_teardown_from_another_thread_ends_the_loop() -> None:
	clock = FakeClock()
	factory = FakeAdapterFactory()
	transcript = FakeTranscript()
	signals = FakeSessionSignals()
	registry = build_command_registry(factory, "x")
	channel = FakeChannel([hello()], clock=clock, on_empty="timeout", timeout_advance=1.0)
	config = SessionConfig(nvda_version="x", heartbeat_timeout=1e9, inactivity_timeout=1e9)
	session = Session(
		channel,
		transcript,
		clock,
		config,
		registry,
		signals,
		FakeAnnouncer(),
		FakeLogCapture(),
		FakeUserPrompter(),
		FakeGestureResolver(),
	)

	thread = threading.Thread(target=session.run)
	thread.start()
	session.request_teardown(TeardownReason.EXTERNAL)
	thread.join(timeout=5.0)

	assert not thread.is_alive()
	assert ("session_closed", TeardownReason.EXTERNAL.value) in transcript.events
	assert factory.speech_source.stopped == 1
	assert signals.ended == 1


def test_teardown_restores_config_keys() -> None:
	factory = FakeAdapterFactory()
	factory.config_accessor.seed(["speech", "synth"], "espeak")
	run_session([hello("silent")], factory=factory)
	assert factory.config_accessor.restore_calls >= 1


def test_teardown_restores_config_even_when_earlier_step_raised() -> None:
	factory = FakeAdapterFactory()
	factory.config_accessor.seed(["speech", "synth"], "espeak")
	factory.speech_source.fail_stop = True
	run = run_session([hello("silent")], factory=factory)
	assert factory.config_accessor.restore_calls >= 1
	assert run.channel.closed is True


def test_config_restore_actually_restores_the_prior_value() -> None:
	store = FakeConfigAccessor()
	store.seed(["speech", "synth"], "espeak")
	store.set(["speech", "synth"], "sapi5")
	assert store.get(["speech", "synth"]) == "sapi5"
	store.restore_all()
	assert store.get(["speech", "synth"]) == "espeak"


def test_request_teardown_cancels_an_open_prompt_window() -> None:
	# On the panic path the caller is NVDA's main thread, joined on the session thread, so an
	# uncancelled window freezes the reader for the rest of the poll.
	clock = FakeClock()
	registry = _fake_registry()
	transcript = FakeTranscript()
	signals = FakeSessionSignals()
	channel = FakeChannel([hello()], clock=clock, on_empty="timeout", timeout_advance=1.0)
	config = SessionConfig(nvda_version="x", heartbeat_timeout=1e9, inactivity_timeout=1e9)
	session = Session(
		channel,
		transcript,
		clock,
		config,
		registry,
		signals,
		FakeAnnouncer(),
		FakeLogCapture(),
		FakeUserPrompter(),
		FakeGestureResolver(),
	)
	prompt = UserPrompt("do the thing", clock)
	session.session_context.set_outstanding_prompt(prompt)

	session.request_teardown(TeardownReason.EXTERNAL)

	with pytest.raises(PromptExpired, match="cancelled"):
		prompt.wait(timeout=1e9)
	assert not prompt.answered


def test_a_session_blocked_on_a_prompt_still_ends_promptly() -> None:
	# A real thread and real sleeps: FakeClock.sleep returns instantly, so it cannot express a hang.
	clock = RealClock()

	def block_on_the_window(ctx: Any, request: Any) -> p.AckResult:
		prompt = UserPrompt("hold the session open", clock)
		ctx.set_outstanding_prompt(prompt)
		prompt.wait(60.0)
		return p.AckResult()

	handler = FakeCommandHandler()
	handler.execute = block_on_the_window  # type: ignore[method-assign]
	registry = _fake_registry(ping=handler)
	session = Session(
		FakeChannel([hello(), command("ping", 2)], clock=FakeClock(), on_empty="closed"),
		FakeTranscript(),
		clock,
		SessionConfig(nvda_version="x", heartbeat_timeout=1e9, inactivity_timeout=1e9),
		registry,
		FakeSessionSignals(),
		FakeAnnouncer(),
		FakeLogCapture(),
		FakeUserPrompter(),
		FakeGestureResolver(),
	)

	thread = threading.Thread(target=session.run, daemon=True)
	thread.start()
	deadline = time.monotonic() + 5.0
	while time.monotonic() < deadline and session.session_context.get_outstanding_prompt() is None:
		time.sleep(0.02)
	assert session.session_context.get_outstanding_prompt() is not None, "no window opened"

	started = time.monotonic()
	session.request_teardown(TeardownReason.EXTERNAL)
	thread.join(timeout=5.0)
	elapsed = time.monotonic() - started

	assert not thread.is_alive(), "the session thread outlived a teardown request"
	assert elapsed < 3.0, (
		f"teardown took {elapsed:.1f}s with a window open; on the panic path that is "
		"time NVDA spends silent, waiting for a poll nobody can answer"
	)


TIGHT_CAP = SilenceCapPolicy(enabled=True, warn_after=10.0, lift_after=20.0)


def quiet_session(
	*,
	silence_cap: SilenceCapPolicy | None = TIGHT_CAP,
	mode: str = "silent",
	seconds: float = 40.0,
	step: float = 5.0,
	interject: dict[float, Any] | None = None,
	factory: FakeAdapterFactory | None = None,
) -> Run:
	"""A session that establishes and says nothing for *seconds*, with both old watchdogs out of reach."""
	events: list[Any] = [hello(mode)]
	interject = interject or {}
	elapsed = 0.0
	while elapsed < seconds:
		events.append(TIMEOUT_EVENT)
		elapsed += step
		if elapsed in interject:
			events.append(interject[elapsed])
	return run_session(
		events,
		on_empty="closed",
		timeout_advance=step,
		heartbeat_timeout=10_000.0,
		inactivity_timeout=10_000.0,
		silence_cap=silence_cap,
		factory=factory,
	)


def test_a_silent_session_that_says_nothing_is_warned_and_then_un_muted() -> None:
	run = quiet_session()
	assert run.announcer.notices == [SilenceNotice.WARNING, SilenceNotice.LIFTED]


def test_the_lift_stops_suppressing_without_stopping_capture() -> None:
	factory = FakeAdapterFactory()
	quiet_session(factory=factory)
	source = factory.speech_source
	assert source.stopped_suppressing == 1
	assert source.suspended == 0, "the lift unregistered the filter; capture was the price"
	assert source.stopped == 1, "capture stopped for some reason other than teardown"


def test_each_notice_is_spoken_once_however_long_the_silence_runs() -> None:
	run = quiet_session(seconds=300.0)
	assert run.announcer.notices == [SilenceNotice.WARNING, SilenceNotice.LIFTED]


def test_an_agent_that_narrates_never_hears_the_cap() -> None:
	run = quiet_session(
		seconds=60.0,
		interject={
			t: command("announce", 200 + int(t), text=f"still working, {t:g}s")
			for t in (5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 55.0)
		},
	)
	assert run.announcer.notices == []
	assert len(run.announcer.announced) == 11


def test_an_announcement_carried_on_a_command_resets_the_clock_too() -> None:
	run = quiet_session(
		seconds=60.0,
		interject={
			t: command(
				"pressGesture",
				200 + int(t),
				gestures=["downArrow"],
				announce=f"pressing down arrow, {t:g}s",
			)
			for t in (5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 55.0)
		},
	)
	assert run.announcer.notices == []
	assert len(run.announcer.announced) == 11


def test_an_announcement_carried_on_typed_text_resets_the_clock_too() -> None:
	run = quiet_session(
		seconds=60.0,
		interject={
			t: command("typeText", 300 + int(t), text="x", announce=f"typing, {t:g}s")
			for t in (5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 55.0)
		},
	)
	assert run.announcer.notices == []


def test_gestures_and_reads_reset_nothing() -> None:
	run = quiet_session(
		interject={
			5.0: command("pressGesture", 201, gestures=["downArrow"]),
			10.0: command("getSpeech", 202, sinceIndex=0),
			15.0: command("ping", 203),
			25.0: command("getState", 204),
		}
	)
	assert run.announcer.notices == [SilenceNotice.WARNING, SilenceNotice.LIFTED]


def test_a_live_session_is_never_capped() -> None:
	run = quiet_session(mode="live", seconds=300.0)
	assert run.announcer.notices == []


def test_an_unattended_machine_is_never_capped() -> None:
	run = quiet_session(silence_cap=SilenceCapPolicy(enabled=False), seconds=300.0)
	assert run.announcer.notices == []


def test_a_prompt_left_open_does_not_trip_the_cap() -> None:
	run = quiet_session(
		seconds=300.0,
		interject={5.0: command("askUser", 201, prompt="have a look at this")},
	)
	assert run.announcer.notices == []


def test_re_suppression_is_audible_and_opens_a_fresh_window() -> None:
	# Lift at 20 s, re-suppressed by the announce at 30 s, then a fresh warning and lift.
	factory = FakeAdapterFactory()
	run = quiet_session(
		seconds=80.0,
		interject={30.0: command("announce", 201, text="back to work")},
		factory=factory,
	)
	assert run.announcer.notices == [
		SilenceNotice.WARNING,
		SilenceNotice.LIFTED,
		SilenceNotice.RESUPPRESSED,
		SilenceNotice.WARNING,
		SilenceNotice.LIFTED,
	]
	assert factory.speech_source.resumed_suppressing == 1


def test_the_transcript_records_what_the_cap_did() -> None:
	run = quiet_session()
	notes = [event[1] for event in run.transcript.events if event[0] == "note"]
	assert any("warning spoken" in note for note in notes)
	assert any("suppression lifted" in note for note in notes)


def test_hello_reports_the_machines_cap_to_the_agent() -> None:
	run = run_session([hello("silent")], silence_cap=TIGHT_CAP)
	assert _result(run.responses()[0])["silenceCap"] == {
		"enabled": True,
		"warnAfterSeconds": 10.0,
		"liftAfterSeconds": 20.0,
	}


def test_hello_reports_an_unattended_machine_honestly() -> None:
	run = run_session([hello("live")], silence_cap=SilenceCapPolicy(enabled=False))
	assert _result(run.responses()[0])["silenceCap"]["enabled"] is False


def test_hello_declares_whether_a_human_is_at_this_machine() -> None:
	run = run_session([hello("live")], attended=True)
	assert _result(run.responses()[0])["attended"] is True


def test_hello_declares_an_empty_room_as_itself() -> None:
	run = run_session([hello("silent")], attended=False)
	assert _result(run.responses()[0])["attended"] is False


def test_attendance_and_the_cap_are_two_facts_and_may_disagree() -> None:
	run = run_session(
		[hello("silent")],
		silence_cap=SilenceCapPolicy(enabled=False),
		attended=True,
	)
	result = _result(run.responses()[0])
	assert result["attended"] is True
	assert result["silenceCap"]["enabled"] is False
