# Unit tests for domain/controllers/session.py -- the LIFECYCLE + dispatcher.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# Since dispatch moved into command handlers, this module tests only what the
# Session itself owns: the handshake, the two watchdogs, teardown's
# restore-on-every-path invariant, and the dispatch MECHANICS (unknown command,
# a handler raising, the pre-hello gate, the resets_inactivity policy). The
# mechanics tests use FakeCommandHandler registries so they do not depend on what
# any real command does; the lifecycle tests use the real registry (with a fake
# AdapterFactory) because they exercise the real hello bootstrap and teardown.
#
# Per-command behaviour lives in tests/unit/domain/controllers/commands/. The
# teardown reason is asserted through the transcript's SESSION CLOSE event.

from __future__ import annotations

import threading
import time
from dataclasses import dataclass
from typing import Any, Mapping

import pytest

from fakes.adapter_factory import FakeAdapterFactory
from fakes.announcer import FakeAnnouncer
from fakes.clock import FakeClock
from fakes.command_handler import FakeCommandHandler
from fakes.config_accessor import FakeConfigAccessor
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
from nvdaMcpBridge.domain.controllers.session import Session, SessionConfig, TeardownReason
from nvdaMcpBridge.domain.entities.user_prompt import PromptExpired, UserPrompt


# -- message builders --------------------------------------------------------


def hello(mode: str = "silent", *, version: int = p.PROTOCOL_VERSION, id: int = 1) -> dict[str, Any]:
	return {"id": id, "cmd": "hello", "params": {"mode": mode, "protocolVersion": version}}


def command(cmd: str, id: int, **params: Any) -> dict[str, Any]:
	return {"id": id, "cmd": cmd, "params": params}


# -- builder helper ----------------------------------------------------------


@dataclass
class Run:
	session: Session
	channel: FakeChannel
	transcript: FakeTranscript
	factory: FakeAdapterFactory
	clock: FakeClock
	signals: FakeSessionSignals
	log_capture: FakeLogCapture

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
	)
	session = Session(channel, transcript, clock, config, registry, signals, announcer, log_capture, user_prompter)
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
	)


def _result(response: dict[str, Any]) -> dict[str, Any]:
	assert response["error"] is None, f"expected a result, got error {response['error']!r}"
	return response["result"]


def _error(response: dict[str, Any]) -> str:
	assert response["error"] is not None, f"expected an error, got result {response['result']!r}"
	return response["error"]["message"]


def _fake_registry(**handlers: FakeCommandHandler) -> dict[str, CommandHandler]:
	"""A registry with a stand-in hello (so tests can reach ESTABLISHED) plus
	whatever fake handlers a mechanics test wants."""
	registry: dict[str, CommandHandler] = {p.Command.HELLO: FakeCommandHandler(available_before_hello=True)}
	registry.update(handlers)
	return registry


# -- handshake (real hello through the dispatcher) ---------------------------


def test_silent_hello_establishes_and_reports() -> None:
	run = run_session([hello("silent")])
	assert run.factory.built_mode is p.CaptureMode.SILENT
	assert run.signals.started == 1  # ascending cue on establish
	result = _result(run.responses()[0])
	assert result["mode"] == "silent"
	assert result["synth"] == "espeak"  # the real synth, read via the announcer
	assert result["reader"] == {"name": "nvda", "version": "2026.1.0"}
	assert result["capabilities"] == [c.value for c in NVDA_CAPABILITIES]
	assert result["logPath"] == run.transcript.path
	assert result["nvdaLogPath"] == run.log_capture.path


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


# -- watchdogs ---------------------------------------------------------------


def test_heartbeat_fires_when_no_message_arrives() -> None:
	run = run_session([hello()], on_empty="timeout", timeout_advance=5.0, heartbeat_timeout=30.0)
	assert run.closed_with(TeardownReason.HEARTBEAT_TIMEOUT)


def test_handler_blocking_past_heartbeat_window_does_not_end_session() -> None:
	# Regression (spec 0016 heartbeat fix): a handler that blocks past the
	# heartbeat window (e.g. waitForSpeech with a caller-supplied timeout of
	# 40 s) must NOT kill the session the instant it returns. The peer's
	# silence while the handler ran was our doing, not evidence it died.
	# The fix: _touch_heartbeat() now runs AFTER _dispatch() too.
	# In this test the "long-running handler" advances the clock by 35 s,
	# well past the 30 s heartbeat window.
	clock = FakeClock()

	def long_running(ctx: object, request: object) -> p.AckResult:
		clock.advance(35.0)
		return p.AckResult()

	handler = FakeCommandHandler()
	handler.execute = long_running  # type: ignore[method-assign]
	registry = _fake_registry(ping=handler)

	# Start the session with a 30 s heartbeat; the handler blocks for 35 s.
	# Before the fix this would tear down with HEARTBEAT_TIMEOUT at the
	# first _check_deadline() after dispatch. With the fix, the
	# post-dispatch heartbeat refresh saves it.
	run = run_session(
		[hello(), command("ping", 2), command("ping", 3)],
		registry=registry,
		clock=clock,
		heartbeat_timeout=30.0,
	)
	# The session survived the long handler AND a follow-up command.
	assert not run.closed_with(TeardownReason.HEARTBEAT_TIMEOUT)
	assert _result(run.responses()[1]) == {"ok": True}
	assert _result(run.responses()[2]) == {"ok": True}


def test_pings_hold_the_heartbeat_but_not_inactivity() -> None:
	# A ping every 10s keeps the 30s heartbeat alive, but pings do not reset the
	# 120s inactivity clock, so inactivity is what eventually fires.
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


# -- teardown: stop capture on every path (speech flows again) ---------------
# There is no synth to restore now: stopping the speech source unregisters the
# suppression filter, so NVDA speaks again. Each step is guarded, so a raise in
# one never skips the channel close or the end cue.


def test_teardown_stops_capture_even_when_the_transcript_raises_on_close() -> None:
	transcript = FakeTranscript(fail_on={"session_closed"})
	run = run_session([hello("silent")], transcript=transcript)
	assert run.factory.speech_source.stopped == 1
	assert run.channel.closed is True


def test_teardown_finishes_even_when_a_source_stop_raises() -> None:
	factory = FakeAdapterFactory()
	factory.speech_source.fail_stop = True
	run = run_session([hello("silent")], factory=factory)
	# The speech source stop raised, but the guard let braille stop, the end cue
	# fire, and the channel close still happen.
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
	# The stop() raise is guarded, so the rest of teardown still completes.
	assert run.factory.speech_source.stopped == 1
	assert run.signals.ended == 1
	assert run.channel.closed is True


def test_teardown_with_an_open_window_leaves_the_tester_audible() -> None:
	# The invariant the whole askUser design is arranged around: a session that
	# dies with an interaction window open must leave the tester HEARING.
	#
	# So teardown must not call resume() on the way out. resume() re-registers the
	# suppression filter -- it makes the tester silent -- and stop() is guarded, so
	# a resume() followed by a raising stop() would strand the tester mute. A window
	# that was open already left the filter unregistered, which is the state
	# teardown wants; stop() then makes it permanent.
	prompter = FakeUserPrompter()
	run = run_session(
		[hello("silent"), command("askUser", 2, prompt="plug in the display")],
		user_prompter=prompter,
	)
	ticket = _result(run.responses()[1])["ticket"]

	assert run.factory.speech_source.suspended == 1, "askUser did not suspend suppression"
	assert run.factory.speech_source.resumed == 0, "teardown re-suppressed a dying session"
	assert run.factory.speech_source.stopped == 1
	# The prompter is told to drop whatever it put in front of the human, so
	# stage 2's dialog cannot outlive the session that opened it.
	assert prompter.cancelled == [ticket]


def test_log_capture_stop_runs_even_when_hello_never_ran() -> None:
	# A pre-hello handshake failure never dispatches hello, so start() never
	# ran -- teardown's stop() call is unconditional regardless (the real
	# adapter's contract is that stop() is then a no-op; see spec 0009).
	run = run_session([command("ping", 1)])
	assert run.log_capture.events == [("stop",)]


# -- dispatch mechanics (fake handlers) --------------------------------------


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


# -- lifecycle commands through dispatch -------------------------------------


def test_bye_acks_then_tears_down() -> None:
	run = run_session([hello(), command("bye", 2)])
	assert _result(run.responses()[1]) == {"ok": True}
	assert run.closed_with(TeardownReason.CLIENT_BYE)
	assert run.channel.closed is True


def test_channel_close_tears_down() -> None:
	run = run_session([hello()])  # script runs out -> EOF -> ChannelClosed
	assert run.closed_with(TeardownReason.CHANNEL_CLOSED)


def test_gesture_error_becomes_an_error_and_the_session_survives() -> None:
	# The real press_gesture handler + a rejecting factory: GestureError is a
	# caught type in dispatch, so this proves that path end to end.
	factory = FakeAdapterFactory(reject=["bad"])
	run = run_session(
		[hello(), command("pressGesture", 2, gestures=["bad"]), command("ping", 3)],
		factory=factory,
	)
	assert "bad" in _error(run.responses()[1])
	assert _result(run.responses()[2]) == {"ok": True}


# -- external teardown -------------------------------------------------------


def test_request_teardown_from_another_thread_ends_the_loop() -> None:
	clock = FakeClock()
	factory = FakeAdapterFactory()
	transcript = FakeTranscript()
	signals = FakeSessionSignals()
	registry = build_command_registry(factory, "x")
	channel = FakeChannel([hello()], clock=clock, on_empty="timeout", timeout_advance=1.0)
	config = SessionConfig(nvda_version="x", heartbeat_timeout=1e9, inactivity_timeout=1e9)
	session = Session(
		channel, transcript, clock, config, registry, signals, FakeAnnouncer(), FakeLogCapture(), FakeUserPrompter()
	)

	thread = threading.Thread(target=session.run)
	thread.start()
	session.request_teardown(TeardownReason.EXTERNAL)
	thread.join(timeout=5.0)

	assert not thread.is_alive()
	assert ("session_closed", TeardownReason.EXTERNAL.value) in transcript.events
	assert factory.speech_source.stopped == 1
	assert signals.ended == 1


# -- teardown: config restoration (spec 0015) --------------------------------


def test_teardown_restores_config_keys() -> None:
    """After a normal session, teardown calls config_accessor.restore_all."""
    factory = FakeAdapterFactory()
    factory.config_accessor.seed(["speech", "synth"], "espeak")
    run_session([hello("silent")], factory=factory)
    # restore_all was called during teardown.
    assert factory.config_accessor.restore_calls >= 1


def test_teardown_restores_config_even_when_earlier_step_raised() -> None:
    """Config restore still runs after a speech source stop raises."""
    factory = FakeAdapterFactory()
    factory.config_accessor.seed(["speech", "synth"], "espeak")
    factory.speech_source.fail_stop = True
    run = run_session([hello("silent")], factory=factory)
    # Even though speech_source.stop raised, config restore still ran.
    assert factory.config_accessor.restore_calls >= 1
    assert run.channel.closed is True


def test_config_restore_actually_restores_the_prior_value() -> None:
    """restore_all restores modified keys to their original values."""
    # Test the fake directly, independent of session teardown.
    store = FakeConfigAccessor()
    store.seed(["speech", "synth"], "espeak")
    # Write modifies the value in memory and records the prior.
    store.set(["speech", "synth"], "sapi5")
    assert store.get(["speech", "synth"]) == "sapi5"
    # Restore brings it back.
    store.restore_all()
    assert store.get(["speech", "synth"]) == "espeak"


def test_request_teardown_cancels_an_open_prompt_window() -> None:
	# Found live, by pressing the panic gesture during an interaction window: NVDA
	# went silent and stayed that way until the poll expired.
	#
	# Teardown is cooperative -- the loop honours it at its next wakeup -- and a
	# handler sitting in waitForUserReply does not reach that wakeup for up to
	# MAX_POLL_TIMEOUT. BridgeServer.stop() joins that thread, and the caller is
	# NVDA's MAIN THREAD on the panic path, so the screen reader freezes for the
	# rest of the poll. Cancelling the window as part of honouring the request is
	# what lets the in-flight wait() return immediately.
	clock = FakeClock()
	registry = _fake_registry()
	transcript = FakeTranscript()
	signals = FakeSessionSignals()
	channel = FakeChannel([hello()], clock=clock, on_empty="timeout", timeout_advance=1.0)
	config = SessionConfig(nvda_version="x", heartbeat_timeout=1e9, inactivity_timeout=1e9)
	session = Session(
		channel, transcript, clock, config, registry, signals,
		FakeAnnouncer(), FakeLogCapture(), FakeUserPrompter(),
	)
	prompt = UserPrompt("do the thing", clock)
	session.session_context.set_outstanding_prompt(prompt)

	session.request_teardown(TeardownReason.EXTERNAL)

	# The prompt is cancelled, so a poll blocked on it aborts at once rather than
	# holding the loop -- and thus the joining main thread -- for its full timeout.
	with pytest.raises(PromptExpired, match="cancelled"):
		prompt.wait(timeout=1e9)
	assert not prompt.answered


def test_a_session_blocked_on_a_prompt_still_ends_promptly() -> None:
	# The same failure from the other end, with a REAL thread and REAL sleeps,
	# because the bug is about wall-clock time on NVDA's main thread and a fake
	# clock cannot express it: FakeClock.sleep returns instantly, so a poll that
	# would hang for a minute in production finishes before the test can look.
	#
	# The handler blocks on a window the way WaitForUserReplyHandler does, rather
	# than going over the wire, because a scripted channel cannot know the ticket
	# askUser has not issued yet.
	clock = RealClock()

	def block_on_the_window(ctx: Any, request: Any) -> p.AckResult:
		prompt = UserPrompt("hold the session open", clock)
		ctx.set_outstanding_prompt(prompt)
		prompt.wait(60.0)  # a minute, unless teardown cuts it short
		return p.AckResult()

	handler = FakeCommandHandler()
	handler.execute = block_on_the_window  # type: ignore[method-assign]
	registry = _fake_registry(ping=handler)
	# The channel gets a FakeClock because its clock only drives timeout advancing,
	# which never happens here (on_empty="closed"); the SESSION and the prompt get
	# the real one, because real sleeping is the whole point.
	session = Session(
		FakeChannel([hello(), command("ping", 2)], clock=FakeClock(), on_empty="closed"),
		FakeTranscript(), clock,
		SessionConfig(nvda_version="x", heartbeat_timeout=1e9, inactivity_timeout=1e9),
		registry, FakeSessionSignals(), FakeAnnouncer(), FakeLogCapture(), FakeUserPrompter(),
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
