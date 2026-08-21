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
	"""The per-session collaborators handed to every command handler."""

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
		#: Whether somebody has asked this session to end. Defaults to "never",
		#: so a hand-built context in a test needs no wiring for it.
		self._teardown_requested = teardown_requested or (lambda: False)
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
		#: Reports which gestures the reader has bound RIGHT NOW, for the guidance
		#: document to print (spec 0029). Always present, like the announcer: it
		#: describes the reader rather than the session, so it never depends on
		#: hello.
		self.gesture_resolver = gesture_resolver
		#: This machine's silence-cap setting (spec 0032), handed over by the
		#: Session at construction because it is a property of the MACHINE rather
		#: than of the session: hello reports it whatever mode was asked for, and
		#: no command can change it.
		self.silence_cap_policy: SilenceCapPolicy | None = silence_cap_policy
		#: Whether a human is expected at this machine (spec 0035), handed over by
		#: the Session for the same reason the policy above is: a property of the
		#: MACHINE, reported by hello whatever mode was asked for, and changed by
		#: no command. Kept BESIDE the policy and never inside it -- the cap is
		#: derived from this fact on the NVDA bridge, and the point of the entry is
		#: that the far end must not reconstruct the fact by inverting the
		#: derivation.
		self.attended: bool = attended
		#: THIS session's live cap, installed by the Session when a silent session
		#: establishes on a capped machine, and None otherwise -- in live mode
		#: nothing is suppressed, so there is no silence to bound.
		self.silence_cap: SilenceCap | None = None
		# Installed by the hello handler; None before it runs.
		self.speech: SpeechBuffer | None = None
		self.braille: BrailleBuffer | None = None
		self.adapters: AdapterSet | None = None
		#: What the agent declared it is standing in for (spec 0029), as received
		#: at hello. A plain string, NOT validated against a known set: the server
		#: owns the set of personas, and a bridge that rejected an unrecognised
		#: one would fail the handshake every time a persona was added upstream
		#: (protocol.md §4). Empty until hello runs, and empty afterwards if the
		#: server declared none.
		self.persona: str = ""
		#: The capture mode this session was established in, as hello received it.
		#: Recorded because the Session must know it to decide whether a silence cap
		#: applies at all (spec 0032): only a silent session suppresses anything.
		#: None until hello runs.
		self.mode: protocol.CaptureMode | None = None
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

	def teardown_requested(self) -> bool:
		"""Whether the session has been asked to end, for a BLOCKING handler to poll.

		Teardown is cooperative: the loop honours a request at its next wakeup,
		which a handler blocked for its whole timeout does not reach. Meanwhile
		the requester may be NVDA's MAIN THREAD -- the panic gesture calls
		BridgeServer.stop(), which joins the session thread -- so a long wait that
		ignored this would freeze the reader for the rest of its timeout, which is
		the exact opposite of what a tester pressing panic needs.

		``waitForUserReply`` solves the same problem by having the request CANCEL
		the outstanding prompt; a wait with no such entity behind it (waitForLog)
		polls this instead.
		"""
		return self._teardown_requested()

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
		"""Suspend speech suppression (for the interaction window).

		Also STOPS the silence cap's clock: the window suspends suppression for its
		whole duration, so the human is hearing everything, and counting silence
		through a stretch with no silence in it would fire the cap at the one
		moment it is provably not needed (spec 0032 Part 2).
		"""
		if self.adapters is not None:
			self.adapters.speech_source.suspend()
		if self.silence_cap is not None:
			self.silence_cap.paused(self.clock.monotonic())

	def resume_speech(self) -> None:
		"""Resume speech suppression after the window closes.

		The speech source restores whichever REGISTERED state was in force, which
		for a session the cap has already lifted is passing through rather than
		suppression -- see the port. Getting that wrong would silently re-mute a
		human the cap had just rescued, from the recovery path itself.
		"""
		if self.adapters is not None:
			self.adapters.speech_source.resume()
		if self.silence_cap is not None:
			self.silence_cap.resumed(self.clock.monotonic())

	def stop_suppressing(self) -> None:
		"""Let speech through to the human while capture continues (the cap's lift)."""
		if self.adapters is not None:
			self.adapters.speech_source.stop_suppressing()

	def resume_suppressing(self) -> None:
		"""Go quiet again after a lift, on a fresh window."""
		if self.adapters is not None:
			self.adapters.speech_source.resume_suppressing()

	def announce_to_human(self, text: str) -> None:
		"""Speak *text* to the human through the synth line, and note that they heard it.

		THE ONE WAY a command may make sound. It exists because the two halves were
		once separate and drifted apart: spec 0032 defined the set of things that
		reset the silence cap as "exactly the set of things that get past the
		suppression", and then only ``announce`` and ``askUser`` reset it -- while
		spec 0025's inline announcement on ``pressGesture``/``typeText``, and
		``setLogLevel``'s confirmation, went out through the same synth and told the
		clock nothing. On 2026-08-20 a session that narrated every few seconds was
		warned at 45 s and un-muted at 90 s anyway, which is the exact failure the
		cap exists to prevent, produced by the cap itself.

		So the definition is mechanical here rather than a rule each handler must
		remember: speaking and noting are one call, and a handler that reaches past
		it for ``self.announcer`` is the thing to catch in review.

		``Announcer.silence_notice`` is deliberately NOT routed through this. The
		cap's own warning is sound the human hears, but it must not restart the
		window it is warning about -- the lift 45 s later is the guarantee, and a
		warning that reset the clock would postpone it forever.
		"""
		self.announcer.announce(text)
		# AFTER the sound, never before: the clock resets when the human was
		# actually told, not when the bridge decided to tell them.
		self.note_audible()

	def note_audible(self) -> None:
		"""The human just heard their own machine: restart the silence cap's window.

		Called by the two commands that produce sound the human hears through the
		suppression -- ``announce`` and ``askUser`` -- AFTER the sound is emitted,
		so the clock resets when the human was actually told rather than when the
		bridge decided to tell them.

		Nothing else may call this. Four hundred gestures in ninety seconds have
		told the human nothing, and the clock is right to say so.

		On a session the cap has already LIFTED, this is also the moment
		suppression re-arms: the agent has narrated, the ordinary flow resumes, and
		a fresh bounded window starts from zero, audibly marked. That is what keeps
		exposure bounded across any number of re-arms. Not while a prompt window is
		open, though -- re-registering the filter there would mute a human who has
		been asked a question and is standing at the keyboard answering it.
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
