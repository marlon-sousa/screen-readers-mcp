# nvdaMcpBridge domain -- SessionContext: the per-session collaborators a handler sees.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: the seam between the Session and its command handlers. A handler is handed
# ONE of these and nothing else, so it can be tested with a hand-built context and
# no Session, no run loop -- which is the whole point of splitting dispatch out.
# DEPENDS ON: the Clock/Transcript ports, the buffer entities, the AdapterSet DTO,
# and TeardownReason -- never NVDA.
# BUILT BY: the Session (once, at session start). Populated by the hello handler,
# which is the bootstrap command that builds the mode-specific state.
#
# Deliberately NARROW. A handler that needs to end the session gets exactly one
# capability -- close(reason) -- not a handle to the Session, so a command can
# never reach into lifecycle internals. The session-scoped entities (speech /
# braille buffers, the AdapterSet) are None until hello installs them; the
# ``*_buffer`` / ``adapters`` accessors assert they are present, so an operational
# handler (only ever dispatched AFTER hello) reads them without a None check.

from __future__ import annotations

from collections.abc import Callable
from typing import TYPE_CHECKING

if TYPE_CHECKING:
	from .... import protocol
	from ...entities.braille_buffer import BrailleBuffer
	from ...entities.speech_buffer import SpeechBuffer
	from ...entities.user_prompt import UserPrompt
	from ...ports.adapter_factory import AdapterSet
	from ...ports.announcer import Announcer
	from ...ports.clock import Clock
	from ...ports.log_capture import LogCapture
	from ...ports.transcript import Transcript
	from ...ports.user_prompter import UserPrompter
	from ..teardown_reason import TeardownReason


class SessionContext:
	"""The per-session collaborators handed to every command handler."""

	def __init__(
		self,
		clock: Clock,
		transcript: Transcript,
		close: Callable[[TeardownReason], None],
		announcer: Announcer,
		log_capture: LogCapture,
		user_prompter: UserPrompter,
	) -> None:
		self.clock = clock
		self.transcript = transcript
		self._close = close
		#: The bridge's line to the reader's real synth: read its name (hello) and
		#: speak hints through it (announce), even during silent capture. Always
		#: present -- it never depends on hello.
		self.announcer = announcer
		#: The tee of NVDA's own log for this session (spec 0009). Always present,
		#: like the transcript; the hello handler starts it.
		self.log_capture = log_capture
		#: Presents prompts to the human and acknowledges answers. Always present
		#: -- like the announcer, it never depends on hello.
		self.user_prompter = user_prompter
		# Installed by the hello handler; None before it runs.
		self.speech: SpeechBuffer | None = None
		self.braille: BrailleBuffer | None = None
		self.adapters: AdapterSet | None = None
		#: At most one outstanding ask at a time.
		self._outstanding_prompt: UserPrompt | None = None
		#: The last 50 command windows: each is (command_id, start_pos,
		#: captured_at_level). Written by the Session when a marking command is
		#: dispatched. There is no stored end (spec 0021): a span runs from its
		#: own start to the NEXT marking command's start, or to the journal's
		#: current position for the still-open last one -- see
		#: command_windows_for, which computes it lazily.
		self.command_windows: list[tuple[int, int, protocol.LogLevel]] = []

	def close(self, reason: TeardownReason) -> None:
		"""Ask the session to end with ``reason`` (used by bye and the panic path).

		The only lifecycle capability a handler gets. Thread-safe via the Session's
		request_teardown, so bye (session thread) and a panic gesture (another
		thread) share one path.
		"""
		self._close(reason)

	def command_window_index(self, command_id: int) -> int | None:
		"""Return the list index for *command_id*, or None if not found."""
		for i, (cid, _start, _level) in enumerate(self.command_windows):
			if cid == command_id:
				return i
		return None

	def command_windows_for(
		self, anchor_index: int, count: int
	) -> list[tuple[int, int, int, protocol.LogLevel]]:
		"""Return up to *count* windows counting back from *anchor_index*, spans included.

		A negative *anchor_index* means "from the end" (Python slice semantics).
		Each returned tuple is ``(command_id, start, end, captured_at_level)``:
		the end is not stored (spec 0021) -- window *i*'s span runs to window
		*i + 1*'s start, or to the journal's current position for the last,
		still-open one, computed here rather than carried by every entry.
		"""
		# Normalise a negative index.
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

	# -- outstanding prompt --------------------------------------------------
	#
	# The SLOT is written only by the session thread (askUser stores, the poll and
	# teardown clear); NVDA's main thread only ever READS it, to answer through the
	# ack gesture. So there is no lock here, and none is needed: the state that two
	# threads genuinely contend for lives inside UserPrompt, which guards it with
	# its own lock. A keypress that arrives just as the poll clears the slot finds
	# nothing to acknowledge and says so, and one that arrives just as the deadline
	# passes answers a cancelled prompt, which is a no-op -- both are the outcomes
	# those races should have.

	def set_outstanding_prompt(self, prompt: UserPrompt) -> bool:
		"""Store *prompt* as the one outstanding ask; returns False if one exists."""
		if self._outstanding_prompt is not None:
			return False
		self._outstanding_prompt = prompt
		return True

	def get_outstanding_prompt(self) -> UserPrompt | None:
		"""The current outstanding prompt, or None."""
		return self._outstanding_prompt

	def clear_outstanding_prompt(self) -> None:
		"""Remove the outstanding prompt (answered, expired, or teardown)."""
		self._outstanding_prompt = None

	# -- speech suppression helpers ------------------------------------------

	def suspend_speech(self) -> None:
		"""Suspend speech suppression (for the interaction window)."""
		if self.adapters is not None:
			self.adapters.speech_source.suspend()

	def resume_speech(self) -> None:
		"""Resume speech suppression after the window closes."""
		if self.adapters is not None:
			self.adapters.speech_source.resume()
