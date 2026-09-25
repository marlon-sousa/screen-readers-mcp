# nvdaMcpBridge domain -- Session: the session-lifecycle controller / dispatcher.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: controller, owning the session lifecycle: the dispatch loop, its three watchdogs, and teardown.
# BUILT BY: wiring.py, which hands it ports, config and the command registry.
# run() executes on the caller's thread; request_teardown() is the only method other threads may call.

from __future__ import annotations

import enum
import threading
from collections.abc import Mapping
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any

from ... import protocol
from ..entities.silence_cap import (
	ATTENDED_DEFAULT,
	SilenceCap,
	SilenceCapAction,
	SilenceCapPolicy,
)
from ..ports.announcer import SilenceNotice
from ..ports.config_accessor import ConfigError
from ..ports.gesture_sender import GestureError
from ..ports.message_channel import ChannelClosed, Timeout
from ..ports.state_setter import StateSetError
from .commands.command_handler import CommandError
from .commands.session_context import SessionContext
from .teardown_reason import TeardownReason

if TYPE_CHECKING:
	from ..ports.announcer import Announcer
	from ..ports.clock import Clock
	from ..ports.gesture_resolver import GestureResolver
	from ..ports.log_capture import LogCapture
	from ..ports.message_channel import MessageChannel
	from ..ports.session_signals import SessionSignals
	from ..ports.transcript import Transcript
	from ..ports.user_prompter import UserPrompter
	from .commands.command_handler import CommandHandler


MAX_COMMAND_WINDOWS: int = 50


@dataclass(frozen=True)
class SessionConfig:
	"""The silence cap is a machine setting from config.ini and must never be settable over the wire."""

	nvda_version: str
	heartbeat_timeout: float = 30.0
	inactivity_timeout: float = 120.0
	silence_cap: SilenceCapPolicy = ATTENDED_DEFAULT
	attended: bool = True


class _State(enum.Enum):
	PRE_HELLO = "pre-hello"
	ESTABLISHED = "established"


class Session:
	def __init__(
		self,
		channel: MessageChannel,
		transcript: Transcript,
		clock: Clock,
		config: SessionConfig,
		registry: Mapping[str, CommandHandler],
		signals: SessionSignals,
		announcer: Announcer,
		log_capture: LogCapture,
		user_prompter: UserPrompter,
		gesture_resolver: GestureResolver,
	) -> None:
		self._channel = channel
		self._transcript = transcript
		self._clock = clock
		self._config = config
		self._registry = registry
		self._signals = signals
		self._log_capture = log_capture

		self._ctx = SessionContext(
			clock,
			transcript,
			self.request_teardown,
			announcer,
			log_capture,
			user_prompter,
			gesture_resolver,
			self._teardown_was_requested,
			config.silence_cap,
			config.attended,
		)
		self._state = _State.PRE_HELLO

		self._last_message_time: float = 0.0
		self._last_command_time: float = 0.0
		# None unless hello established a silent session on a capped machine.
		self._cap: SilenceCap | None = None

		# Honoured by the loop at its next wakeup.
		self._external_lock = threading.Lock()
		self._external_reason: TeardownReason | None = None

		self._reason: TeardownReason | None = None
		self._torn_down = False

	def run(self) -> None:
		now = self._clock.monotonic()
		self._last_message_time = now
		self._last_command_time = now
		try:
			self._loop()
		finally:
			self._teardown()

	@property
	def session_context(self) -> SessionContext:
		return self._ctx

	def request_teardown(self, reason: TeardownReason) -> None:
		"""Thread-safe; the first request wins.

		Cancelling the open prompt is required: the panic gesture joins the session thread from NVDA's main
		thread, and a handler blocked in `waitForUserReply` would otherwise freeze NVDA for the whole poll.
		"""
		with self._external_lock:
			if self._external_reason is None:
				self._external_reason = reason
		prompt = self._ctx.get_outstanding_prompt()
		if prompt is not None:
			prompt.cancel()

	def _teardown_was_requested(self) -> bool:
		"""Polled by blocking handlers with no prompt to cancel, such as waitForLog."""
		with self._external_lock:
			return self._external_reason is not None

	def _loop(self) -> None:
		while self._reason is None:
			self._absorb_external()
			if self._reason is not None:
				break
			try:
				raw = self._channel.read_message()
			except ChannelClosed:
				self._reason = TeardownReason.CHANNEL_CLOSED
				break
			except protocol.ValidationError as exc:
				self._on_unreadable(exc)
				self._check_deadline()
				self._check_silence()
				continue
			if isinstance(raw, Timeout):
				self._check_deadline()
				self._check_silence()
				continue
			self._touch_heartbeat()
			self._dispatch(raw)
			# Refreshed after dispatch too: the peer's silence while a handler blocked was ours.
			self._touch_heartbeat()
			self._check_deadline()
			self._check_silence()

	def _absorb_external(self) -> None:
		with self._external_lock:
			if self._external_reason is not None and self._reason is None:
				self._reason = self._external_reason

	def _on_unreadable(self, exc: protocol.ValidationError) -> None:
		# Garbage before hello is not our client; mid-session it is noted and survived.
		if self._state is _State.PRE_HELLO:
			self._reason = TeardownReason.HANDSHAKE_FAILED
			return
		self._touch_heartbeat()
		self._transcript.note(f"unreadable message: {exc}")

	def _touch_heartbeat(self) -> None:
		self._last_message_time = self._clock.monotonic()

	def _check_deadline(self) -> None:
		if self._reason is not None:
			return
		now = self._clock.monotonic()
		if now - self._last_message_time >= self._config.heartbeat_timeout:
			self._reason = (
				TeardownReason.HANDSHAKE_FAILED
				if self._state is _State.PRE_HELLO
				else TeardownReason.HEARTBEAT_TIMEOUT
			)
			return
		if (
			self._state is _State.ESTABLISHED
			and now - self._last_command_time >= self._config.inactivity_timeout
		):
			self._reason = TeardownReason.INACTIVITY_TIMEOUT

	def _arm_silence_cap(self) -> None:
		"""Only a silent session on a machine not declared unattended gets a cap."""
		policy = self._config.silence_cap
		if not policy.enabled or self._ctx.mode is not protocol.CaptureMode.SILENT:
			return
		cap = SilenceCap(policy, self._clock.monotonic())
		self._cap = cap
		# The context holds the same cap, so audible commands and prompt windows reach it.
		self._ctx.silence_cap = cap

	def _check_silence(self) -> None:
		"""Called wherever ``_check_deadline`` is, so it runs even when nothing arrives.

		Every step is guarded, and the lift runs before the steps that only report it.
		"""
		cap = self._cap
		if cap is None or self._reason is not None:
			return
		action = cap.check(self._clock.monotonic())
		if action is SilenceCapAction.NONE:
			return
		if action is SilenceCapAction.LIFT:
			self._guard(self._ctx.stop_suppressing)
			self._guard(
				lambda: self._transcript.note(
					f"silence cap: nothing audible for {cap.policy.lift_after:g} s; "
					f"suppression lifted, capture continues"
				)
			)
			self._guard(lambda: self._ctx.announcer.silence_notice(SilenceNotice.LIFTED))
			return
		self._guard(
			lambda: self._transcript.note(
				f"silence cap: nothing audible for {cap.policy.warn_after:g} s; warning spoken"
			)
		)
		self._guard(lambda: self._ctx.announcer.silence_notice(SilenceNotice.WARNING))

	def _dispatch(self, raw: dict[str, Any]) -> None:
		try:
			request = protocol.from_dict(protocol.Request, raw)
		except protocol.ValidationError as exc:
			self._reply_command_error(self._extract_id(raw), f"invalid request: {exc}")
			return

		handler = self._registry.get(request.cmd)
		pre_hello = self._state is _State.PRE_HELLO
		if handler is None or (pre_hello and not handler.available_before_hello):
			if pre_hello:
				self._reply_command_error(request.id, "handshake: expected hello")
			else:
				self._reply_error(request.id, f"unknown command: {request.cmd!r}")
			return
		if not pre_hello and handler.available_before_hello:
			self._reply_error(request.id, "session already established")
			return

		if handler.resets_inactivity:
			self._last_command_time = self._clock.monotonic()

		# Opened before execute, so a failed command still gets its window; a journal that cannot be read
		# costs the window, never the command.
		if handler.marks_log:
			try:
				start_pos = self._log_capture.position()
				captured_at = self._log_capture.current_level
			except Exception:
				pass
			else:
				self._open_window(request.id, start_pos, captured_at)

		try:
			result = handler.execute(self._ctx, request)
		except (protocol.ValidationError, GestureError, ConfigError, StateSetError, CommandError) as exc:
			self._reply_command_error(request.id, str(exc))
			return
		except Exception as exc:  # a handler blew up unexpectedly; the session survives
			self._reply_command_error(request.id, str(exc))
			return

		self._reply(request.id, result)
		if pre_hello:
			self._state = _State.ESTABLISHED
			self._arm_silence_cap()
			# Guarded: a failed cue must not break the just-established session.
			self._guard(lambda: self._signals.session_started(self._ctx.persona))

	def _open_window(self, request_id: int, start_pos: int, captured_at: protocol.LogLevel) -> None:
		windows = self._ctx.command_windows
		windows.append((request_id, start_pos, captured_at))
		if len(windows) > MAX_COMMAND_WINDOWS:
			del windows[:-MAX_COMMAND_WINDOWS]

	def _teardown(self) -> None:
		"""Run exactly once, in ``finally``; every step is guarded so one failure never skips the rest."""
		if self._torn_down:
			return
		self._torn_down = True
		reason = self._reason if self._reason is not None else TeardownReason.EXTERNAL
		ctx = self._ctx

		# Never call speech_source.resume() here: it re-registers suppression, and if stop() then failed the
		# tester would be left mute.
		prompt = ctx.get_outstanding_prompt()
		if prompt is not None:
			ticket = prompt.ticket
			prompt.cancel()
			ctx.clear_outstanding_prompt()
			self._guard(lambda: ctx.user_prompter.cancel(ticket))

		self._guard(self._log_capture.stop)
		if ctx.adapters is not None:
			self._guard(ctx.adapters.speech_source.stop)
			self._guard(ctx.adapters.braille_source.stop)
			self._guard(ctx.adapters.config_accessor.restore_all)
		self._guard(lambda: self._transcript.session_closed(reason.value))
		if self._state is _State.ESTABLISHED:
			self._guard(self._signals.session_ended)
		self._guard(self._channel.close)

	@staticmethod
	def _guard(action: Any) -> None:
		try:
			action()
		except Exception:
			# Swallowed so the remaining steps, above all unregistering suppression, still run.
			pass

	def _reply(self, request_id: int, result: Any) -> None:
		self._safe_write(protocol.Response(id=request_id, result=result))

	def _reply_error(self, request_id: int | None, message: str) -> None:
		if request_id is None:
			self._transcript.note(f"unattributable error: {message}")
			return
		self._safe_write(protocol.Response(id=request_id, error=protocol.ErrorInfo(message=message)))

	def _reply_command_error(self, request_id: int | None, message: str) -> None:
		self._reply_error(request_id, message)
		if self._state is _State.PRE_HELLO:
			self._reason = TeardownReason.HANDSHAKE_FAILED

	def _safe_write(self, response: protocol.Response) -> None:
		# A dead channel is caught by the next read, which raises ChannelClosed.
		try:
			self._channel.write(response)
		except Exception:
			pass

	@staticmethod
	def _extract_id(raw: dict[str, Any]) -> int | None:
		candidate = raw.get("id")
		if isinstance(candidate, bool) or not isinstance(candidate, int):
			return None
		return candidate
