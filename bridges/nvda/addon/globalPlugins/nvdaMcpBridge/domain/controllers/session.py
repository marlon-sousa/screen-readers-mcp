# nvdaMcpBridge domain -- Session: the session-lifecycle controller / dispatcher.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: controller. Owns the session LIFECYCLE and nothing command-specific:
# one dispatch loop guarded by two watchdogs (heartbeat, command-inactivity), and
# a teardown that restores the user's synth on every exit path. Per-command logic
# lives in commands/ handlers; the Session only reads a message, looks the command
# up in the injected registry, calls handler.execute(ctx, request), and wraps the
# result (or the error) into a Response.
# HANDED (by wiring.py): a MessageChannel, a Transcript, a Clock, a SessionConfig,
#   a LogCapture, and the command registry -- ports/config only. It does NOT
#   know the AdapterFactory; that lives inside the hello handler.
# BUILDS: the SessionContext handed to every handler (and populated by hello).
#
# One loop, one phase flag. Pre-hello only `hello` is accepted and any failure
# ends the handshake; post-hello the session is tolerant (an error reply, keep
# going). ``while self._reason is None`` is the whole loop: every exit sets the
# reason, a TIMEOUT sets nothing and polls again. run() executes on the caller's
# thread; request_teardown() is the only method other threads may call.

from __future__ import annotations

import enum
import threading
from collections.abc import Mapping
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any

from ... import protocol
from ..ports.config_accessor import ConfigError
from ..ports.gesture_sender import GestureError
from ..ports.message_channel import ChannelClosed, Timeout
from .commands.command_handler import CommandError
from .commands.session_context import SessionContext
from .teardown_reason import TeardownReason

if TYPE_CHECKING:
	from ..ports.announcer import Announcer
	from ..ports.clock import Clock
	from ..ports.log_capture import LogCapture
	from ..ports.message_channel import MessageChannel
	from ..ports.session_signals import SessionSignals
	from ..ports.transcript import Transcript
	from ..ports.user_prompter import UserPrompter
	from .commands.command_handler import CommandHandler


#: How many command log-windows the context keeps (spec 0020). Enough that a
#: debugging loop can still reach the command that failed several commands ago,
#: bounded because each entry pins nothing but four numbers.
MAX_COMMAND_WINDOWS: int = 50


@dataclass(frozen=True)
class SessionConfig:
	"""Per-session settings wiring hands the controller.

	The watchdog windows are separate on purpose: the heartbeat proves the
	harness PROCESS is alive (any message resets it), while command inactivity
	proves the AGENT is still testing (only a real command -- not a ping --
	resets it). See RFC 0001's session-lifecycle section.
	"""

	nvda_version: str
	heartbeat_timeout: float = 30.0
	inactivity_timeout: float = 120.0


class _State(enum.Enum):
	"""Whether the handshake has completed. Private to the dispatch loop."""

	PRE_HELLO = "pre-hello"
	ESTABLISHED = "established"


class Session:
	"""Runs a single bridge session: handshake, dispatch, watchdogs, teardown."""

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
		)
		self._state = _State.PRE_HELLO

		# Watchdog bookkeeping (monotonic seconds); seeded in run().
		self._last_message_time: float = 0.0
		self._last_command_time: float = 0.0

		# Cross-thread teardown request; the loop honours it at the next wakeup.
		self._external_lock = threading.Lock()
		self._external_reason: TeardownReason | None = None

		self._reason: TeardownReason | None = None
		self._torn_down = False

	# -- public API ----------------------------------------------------------

	def run(self) -> None:
		"""Run the whole session on the caller's thread; always tears down."""
		now = self._clock.monotonic()
		self._last_message_time = now
		self._last_command_time = now
		try:
			self._loop()
		finally:
			self._teardown()

	@property
	def session_context(self) -> SessionContext:
		"""The per-session context, for the ack gesture to reach the prompt."""
		return self._ctx

	def request_teardown(self, reason: TeardownReason) -> None:
		"""Ask the session to end (thread-safe; honoured at the next wakeup).

		The SessionContext's close() is wired to this, so a command (bye) and
		session C's plugin terminate / panic gesture share one path. First
		request wins.

		Cancelling an open interaction window is part of honouring the request, not
		a courtesy. Teardown is COOPERATIVE -- the loop notices at its next wakeup
		-- and a handler blocked on `waitForUserReply` does not reach that wakeup
		for as long as its poll lasts, up to MAX_POLL_TIMEOUT. Meanwhile the caller
		may be NVDA's MAIN THREAD: the panic gesture calls BridgeServer.stop(),
		which joins the session thread. Without this the panic gesture FREEZES NVDA
		for the rest of the poll -- no speech at all -- which is the exact opposite
		of what a tester pressing panic needs. Cancelling makes the in-flight
		`wait()` raise at once, so the handler returns and the loop can see this.
		"""
		with self._external_lock:
			if self._external_reason is None:
				self._external_reason = reason
		prompt = self._ctx.get_outstanding_prompt()
		if prompt is not None:
			prompt.cancel()

	# -- the one dispatch loop ----------------------------------------------

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
				continue
			if isinstance(raw, Timeout):
				self._check_deadline()
				continue
			self._touch_heartbeat()
			self._dispatch(raw)
			# Refresh the heartbeat AFTER dispatch too, so a handler that
			# blocks past the heartbeat window (e.g. waitForSpeech with a
			# caller-supplied timeout of 40 s) does not kill the session the
			# instant it returns. The peer's silence while the handler ran
			# was our doing, not evidence it died.  (spec 0016 heartbeat fix)
			self._touch_heartbeat()
			self._check_deadline()

	def _absorb_external(self) -> None:
		with self._external_lock:
			if self._external_reason is not None and self._reason is None:
				self._reason = self._external_reason

	def _on_unreadable(self, exc: protocol.ValidationError) -> None:
		# Bytes arrived, so the peer is alive -- but a garbage line before hello
		# is not our client, while mid-session it is merely noted and survived.
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

	# -- dispatch ------------------------------------------------------------

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

		# A real command resets inactivity; a ping proves liveness only.
		if handler.resets_inactivity:
			self._last_command_time = self._clock.monotonic()

		# Open this command's log span BEFORE dispatch (spec 0021): everything the
		# journal records from here until the NEXT marking command opens belongs
		# to this one -- there is no end to measure afterwards, so nothing here
		# waits on how execute() turns out. A handler that sets marks_log=False
		# (getLog) opens nothing, so the default anchor is never the getLog that
		# just ran. Guarded: a journal that cannot be read costs the window, never
		# the command -- "a failed command still gets its window" now falls out
		# for free, since the window is already recorded before execute can fail.
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
		except (protocol.ValidationError, GestureError, ConfigError, CommandError) as exc:
			self._reply_command_error(request.id, str(exc))
			return
		except Exception as exc:  # a handler blew up unexpectedly; the session survives
			self._reply_command_error(request.id, str(exc))
			return

		self._reply(request.id, result)
		if pre_hello:
			self._state = _State.ESTABLISHED
			# Two ascending tones: the bridge is now controlling NVDA. Guarded so a
			# beep failure never breaks the just-established session.
			self._guard(self._signals.session_started)

	def _open_window(self, request_id: int, start_pos: int, captured_at: protocol.LogLevel) -> None:
		"""Record this command's span start, keeping the last N.

		The span's end is never stored: it is the next marking command's start,
		or the journal's current position while this one is still the last
		(SessionContext.command_windows_for computes it lazily).
		"""
		windows = self._ctx.command_windows
		windows.append((request_id, start_pos, captured_at))
		if len(windows) > MAX_COMMAND_WINDOWS:
			del windows[:-MAX_COMMAND_WINDOWS]

	# -- teardown ------------------------------------------------------------

	def _teardown(self) -> None:
		"""Run exactly once, in ``finally``, on every exit path.

		Each step is individually guarded so a failure in one never skips the
		rest -- above all, ``restore()`` runs whenever an AdapterSet was built
		(idempotent by contract), and neither a raising transcript nor a raising
		restore can stop the channel from closing. Steps for state hello never
		built are naturally skipped.
		"""
		if self._torn_down:
			return
		self._torn_down = True
		reason = self._reason if self._reason is not None else TeardownReason.EXTERNAL
		ctx = self._ctx

		# Cancel any outstanding prompt: a poll still in flight raises
		# PromptExpired rather than waiting out a window nobody can answer, and
		# the prompter drops whatever it put in front of the human. Safe even if
		# hello never ran (no prompt, no adapters).
		#
		# Deliberately NO speech_source.resume() here. resume() RE-REGISTERS the
		# suppression filter -- it makes the tester silent -- so calling it on
		# the way out would reinstall suppression microseconds before stop()
		# removes it, and if stop() then raised (it is guarded, so the failure is
		# swallowed) the tester would be left MUTE. A window that was open left
		# the filter unregistered, which is exactly the state teardown wants.
		prompt = ctx.get_outstanding_prompt()
		if prompt is not None:
			ticket = prompt.ticket
			prompt.cancel()
			ctx.clear_outstanding_prompt()
			self._guard(lambda: ctx.user_prompter.cancel(ticket))

		# First: a bumped log level (if hello requested one) is held no longer
		# than it must be. Safe even if hello never started capture (or never ran).
		self._guard(self._log_capture.stop)
		if ctx.adapters is not None:
			# Stopping the speech source unregisters the speak() filter (silent
			# mode), so NVDA's speech flows again at once -- there is no synth to
			# restore, because none was ever swapped.
			self._guard(ctx.adapters.speech_source.stop)
			self._guard(ctx.adapters.braille_source.stop)
			# Restore every config key this session touched (spec 0015,
			# entry 11.1). Guarded so a failed restore never skips the
			# remaining teardown steps.
			self._guard(ctx.adapters.config_accessor.restore_all)
		self._guard(lambda: self._transcript.session_closed(reason.value))
		if self._state is _State.ESTABLISHED:
			# Two descending tones: control released. Only if a session actually
			# established (no end-cue for a connection that never said hello).
			self._guard(self._signals.session_ended)
		self._guard(self._channel.close)

	@staticmethod
	def _guard(action: Any) -> None:
		try:
			action()
		except Exception:
			# Teardown must complete on every path; a failure here is swallowed
			# so the remaining steps (crucially, the synth restore) still run.
			pass

	# -- reply helpers -------------------------------------------------------

	def _reply(self, request_id: int, result: Any) -> None:
		self._safe_write(protocol.Response(id=request_id, result=result))

	def _reply_error(self, request_id: int | None, message: str) -> None:
		if request_id is None:
			# No id to attribute the error to; the transcript still records it.
			self._transcript.note(f"unattributable error: {message}")
			return
		self._safe_write(protocol.Response(id=request_id, error=protocol.ErrorInfo(message=message)))

	def _reply_command_error(self, request_id: int | None, message: str) -> None:
		"""Reply an error; if this happens before hello, it ends the handshake."""
		self._reply_error(request_id, message)
		if self._state is _State.PRE_HELLO:
			self._reason = TeardownReason.HANDSHAKE_FAILED

	def _safe_write(self, response: protocol.Response) -> None:
		# A dead channel during a reply is caught by the next read (which raises
		# ChannelClosed and tears down), so a failed write here is swallowed
		# rather than crashing the loop before the read can observe the close.
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
