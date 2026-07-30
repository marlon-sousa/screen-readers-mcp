# nvdaMcpBridge domain -- UserPrompt: one outstanding ask to the human.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: entity. Represents one in-flight ask: its ticket, the prompt, whether the
# human answered, any text they entered (empty in stage 1), and an absolute
# deadline 300 s from minting. Thread-safe (the NVDA main thread writes the answer
# while the session thread polls); guarded by a lock.
# DEPENDS ON: Clock (injected), for the deadline and the timed-wait loop.
# BUILT BY: AskUserHandler; cleared by WaitForUserReplyHandler and session teardown.
#
# The deadline is absolute (set once, never extended), so a window cannot be kept
# alive by polling it. The window's own lifetime is its own, not the poll's -- a
# poll miss leaves the window open, so present-then-poll survives transient
# failures. Only an answer, the deadline, or teardown closes it.
#
# The deadline is evaluated inside wait(), so it is a POLL that observes the
# expiry, not a timer: an agent that asks and then stops polling entirely leaves
# the window open until the session's own watchdogs end the session, whose
# teardown cancels the prompt and lifts suppression. That direction is the safe
# one (the tester keeps hearing speech, which is what an abandoned window should
# leave behind), and it is why nothing here needs a thread of its own.

from __future__ import annotations

import threading
import uuid
from typing import TYPE_CHECKING

if TYPE_CHECKING:
	from ..ports.clock import Clock

#: How long the human gets before the window closes on its own. Chosen long enough
#: for "find the password, plug in the display, do the thing" and short enough that
#: a crashed agent cannot leave capture suspended forever.
_WINDOW_LIFETIME: float = 300.0


class UserPrompt:
	"""One ask, shared between the session thread (poll) and the main thread (answer)."""

	def __init__(self, prompt: str, clock: Clock) -> None:
		self._lock = threading.Lock()
		self.ticket: str = uuid.uuid4().hex[:12]
		self.prompt: str = prompt
		self.answered: bool = False
		#: Always empty in stage 1; stage 2's dialog populates it.
		self.text: str = ""
		#: Absolute monotonic deadline; expired → answered=false, cancelled.
		self.deadline: float = clock.monotonic() + _WINDOW_LIFETIME
		self._cancelled: bool = False
		self._clock = clock

	# -- answering (main thread) -----------------------------------------------

	def answer(self, text: str = "") -> None:
		"""Record the human's acknowledgement. Called from NVDA's main thread."""
		with self._lock:
			if self._cancelled or self.answered:
				return
			self.answered = True
			self.text = text

	def cancel(self) -> None:
		"""Cancel the prompt without an answer (deadline or teardown)."""
		with self._lock:
			self._cancelled = True

	# -- polling (session thread) -----------------------------------------------

	def wait(self, timeout: float) -> bool:
		"""Block for at most ``timeout`` seconds or until answered/expired/cancelled.

		Returns ``True`` when answered, ``False`` for a poll miss (timeout elapsed
		but the window is still open), and raises ``PromptExpired`` when the
		window's own deadline has passed or the prompt was cancelled.
		"""
		deadline = self._clock.monotonic() + timeout
		while True:
			with self._lock:
				if self.answered:
					return True
				if self._cancelled:
					raise PromptExpired(self.ticket, "cancelled")
				if self._clock.monotonic() >= self.deadline:
					self._cancelled = True
					raise PromptExpired(self.ticket, "deadline")
			# A true poll miss: window still open, just nothing yet.
			if self._clock.monotonic() >= deadline:
				return False
			self._clock.sleep(0.1)


class PromptExpired(Exception):
	"""Raised when a wait on a prompt that has expired or been cancelled."""

	def __init__(self, ticket: str, reason: str) -> None:
		super().__init__(f"prompt {ticket!r} expired: {reason}")
		self.ticket = ticket
		self.reason = reason
