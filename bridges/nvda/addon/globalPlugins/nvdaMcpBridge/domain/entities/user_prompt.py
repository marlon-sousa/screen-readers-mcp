# nvdaMcpBridge domain -- UserPrompt: one outstanding ask to the human.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: entity, one in-flight ask to the human with its ticket, answer and absolute deadline.
# BUILT BY: AskUserHandler; cleared by WaitForUserReplyHandler and session teardown.
# Thread-safe: NVDA's main thread writes the answer while the session thread polls.
# The deadline is only observed by a poll; an agent that stops polling leaves the window open until
# the session's watchdogs end the session.

from __future__ import annotations

import threading
import uuid
from typing import TYPE_CHECKING

if TYPE_CHECKING:
	from ..ports.clock import Clock

# Long enough to fetch a password or plug in a display; short enough that a crashed agent cannot
# leave capture suspended forever.
_WINDOW_LIFETIME: float = 300.0


class UserPrompt:
	def __init__(self, prompt: str, clock: Clock) -> None:
		self._lock = threading.Lock()
		self.ticket: str = uuid.uuid4().hex[:12]
		self.prompt: str = prompt
		self.answered: bool = False
		# Empty until a dialog can collect text.
		self.text: str = ""
		# Absolute and never extended, so polling cannot keep a window alive.
		self.deadline: float = clock.monotonic() + _WINDOW_LIFETIME
		self._cancelled: bool = False
		self._clock = clock

	def answer(self, text: str = "") -> None:
		"""Called from NVDA's main thread."""
		with self._lock:
			if self._cancelled or self.answered:
				return
			self.answered = True
			self.text = text

	def cancel(self) -> None:
		with self._lock:
			self._cancelled = True

	def wait(self, timeout: float) -> bool:
		"""``True`` when answered, ``False`` on a poll miss; raises ``PromptExpired`` once closed."""
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
			if self._clock.monotonic() >= deadline:
				return False
			self._clock.sleep(0.1)


class PromptExpired(Exception):
	def __init__(self, ticket: str, reason: str) -> None:
		super().__init__(f"prompt {ticket!r} expired: {reason}")
		self.ticket = ticket
		self.reason = reason
