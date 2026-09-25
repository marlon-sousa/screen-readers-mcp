# nvdaMcpBridge domain -- SessionContext: the per-session collaborators a handler sees.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: parameter object, the per-session collaborators a command handler is handed instead of the Session.
# BUILT BY: the Session at session start; populated by the hello handler.
# The buffers and AdapterSet are None until hello installs them; the accessors assert their presence.

from __future__ import annotations

from collections.abc import Callable
from typing import TYPE_CHECKING

from ...ports.announcer import SilenceNotice

if TYPE_CHECKING:
	from .... import protocol
	from ...entities.braille_buffer import BrailleBuffer
	from ...entities.silence_cap import SilenceCap, SilenceCapPolicy
	from ...entities.speech_buffer import SpeechBuffer
	from ...entities.user_prompt import UserPrompt
	from ...ports.adapter_factory import AdapterSet
	from ...ports.announcer import Announcer
	from ...ports.clock import Clock
	from ...ports.gesture_resolver import GestureResolver
	from ...ports.log_capture import LogCapture
	from ...ports.transcript import Transcript
	from ...ports.user_prompter import UserPrompter
	from ..teardown_reason import TeardownReason


class SessionContext:
	def __init__(
		self,
		clock: Clock,
		transcript: Transcript,
		close: Callable[[TeardownReason], None],
		announcer: Announcer,
		log_capture: LogCapture,
		user_prompter: UserPrompter,
		gesture_resolver: GestureResolver,
		teardown_requested: Callable[[], bool] | None = None,
		silence_cap_policy: SilenceCapPolicy | None = None,
		attended: bool = True,
	) -> None:
		self.clock = clock
		self.transcript = transcript
		self._close = close
		self._teardown_requested = teardown_requested or (lambda: False)
		self.announcer = announcer
		self.log_capture = log_capture
		self.user_prompter = user_prompter
		self.gesture_resolver = gesture_resolver
		self.silence_cap_policy: SilenceCapPolicy | None = silence_cap_policy
		# Kept beside the policy: the far end must not reconstruct it by inverting the cap's derivation.
		self.attended: bool = attended
		# None in live mode, where nothing is suppressed.
		self.silence_cap: SilenceCap | None = None
		self.speech: SpeechBuffer | None = None
		self.braille: BrailleBuffer | None = None
		self.adapters: AdapterSet | None = None
		# Not validated: the server owns the set of personas. Empty if none was declared.
		self.persona: str = ""
		self.mode: protocol.CaptureMode | None = None
		self._outstanding_prompt: UserPrompt | None = None
		# (command_id, start_pos, captured_at_level); a span's end is the next window's start.
		self.command_windows: list[tuple[int, int, protocol.LogLevel]] = []

	def close(self, reason: TeardownReason) -> None:
		"""Thread-safe: bye on the session thread and the panic gesture on another share this path."""
		self._close(reason)

	def teardown_requested(self) -> bool:
		"""Blocking handlers must poll this, or the panic gesture freezes NVDA for the whole wait."""
		return self._teardown_requested()

	def command_window_index(self, command_id: int) -> int | None:
		for i, (cid, _start, _level) in enumerate(self.command_windows):
			if cid == command_id:
				return i
		return None

	def command_windows_for(
		self, anchor_index: int, count: int
	) -> list[tuple[int, int, int, protocol.LogLevel]]:
		"""Return up to *count* windows ending at *anchor_index*, as ``(command_id, start, end, level)``.

		A negative *anchor_index* counts from the end; the last window ends at the journal's current position.
		"""
		if anchor_index < 0:
			anchor_index = len(self.command_windows) + anchor_index
		if anchor_index < 0 or anchor_index >= len(self.command_windows):
			return []
		start_idx = max(0, anchor_index - count + 1)
		selected = self.command_windows[start_idx : anchor_index + 1]
		result: list[tuple[int, int, int, protocol.LogLevel]] = []
		for i, (command_id, start, level) in enumerate(selected, start=start_idx):
			end = (
				self.command_windows[i + 1][1]
				if i + 1 < len(self.command_windows)
				else self.log_capture.position()
			)
			result.append((command_id, start, end, level))
		return result

	@property
	def speech_buffer(self) -> SpeechBuffer:
		assert self.speech is not None, "speech buffer read before hello installed it"
		return self.speech

	@property
	def braille_buffer(self) -> BrailleBuffer:
		assert self.braille is not None, "braille buffer read before hello installed it"
		return self.braille

	@property
	def adapter_set(self) -> AdapterSet:
		assert self.adapters is not None, "adapters read before hello installed them"
		return self.adapters

	# The prompt slot is written only by the session thread; NVDA's main thread only reads it.

	def set_outstanding_prompt(self, prompt: UserPrompt) -> bool:
		if self._outstanding_prompt is not None:
			return False
		self._outstanding_prompt = prompt
		return True

	def get_outstanding_prompt(self) -> UserPrompt | None:
		return self._outstanding_prompt

	def clear_outstanding_prompt(self) -> None:
		self._outstanding_prompt = None

	def suspend_speech(self) -> None:
		"""Also pauses the silence cap, since the human hears everything while suppression is suspended."""
		if self.adapters is not None:
			self.adapters.speech_source.suspend()
		if self.silence_cap is not None:
			self.silence_cap.paused(self.clock.monotonic())

	def resume_speech(self) -> None:
		"""Restores the registered state, which after a cap lift is passthrough; re-muting here is the bug."""
		if self.adapters is not None:
			self.adapters.speech_source.resume()
		if self.silence_cap is not None:
			self.silence_cap.resumed(self.clock.monotonic())

	def stop_suppressing(self) -> None:
		if self.adapters is not None:
			self.adapters.speech_source.stop_suppressing()

	def resume_suppressing(self) -> None:
		if self.adapters is not None:
			self.adapters.speech_source.resume_suppressing()

	def announce_to_human(self, text: str) -> None:
		"""The only way a command may make sound: speaking and resetting the silence cap are one call.

		The cap's own warning uses ``Announcer.silence_notice`` instead, so it cannot postpone the lift.
		"""
		self.announcer.announce(text)
		# After the sound: the clock resets when the human was told.
		self.note_audible()

	def note_audible(self) -> None:
		"""Restart the silence cap's window; call only after sound the human heard, never for gestures.

		On a lifted cap this re-arms suppression, except while a prompt window is open.
		"""
		cap = self.silence_cap
		if cap is None:
			return
		now = self.clock.monotonic()
		if cap.lifted and not cap.is_paused:
			self.resume_suppressing()
			cap.resuppressed(now)
			self.transcript.note("silence cap: suppression re-armed after an announcement")
			self.announcer.silence_notice(SilenceNotice.RESUPPRESSED)
			return
		cap.heard(now)
