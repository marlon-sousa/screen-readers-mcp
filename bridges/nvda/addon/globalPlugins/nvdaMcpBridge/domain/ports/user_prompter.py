# nvdaMcpBridge domain -- the UserPrompter port: ask the human and acknowledge.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: domain port. The mechanism that presents a prompt to the human (beeps,
# spoken text through the real synth, and an instruction naming the gesture) and
# cancels it.
# USED BY: AskUserHandler (present) and teardown (cancel).
# IMPLEMENTED BY: adapters/nvda_user_prompter.py (cue beeps + synth.speak +
#                 run_on_main); tests/fakes/user_prompter.py.

from __future__ import annotations

from abc import ABC, abstractmethod


class UserPrompter(ABC):
	"""Presents a prompt to the human and can cancel it."""

	@abstractmethod
	def present(self, prompt: str, ticket: str) -> None:
		"""Announce the prompt audibly: beeps, the prompt text, the gesture name.

		Called from the session thread; the implementation marshals to the
		main thread.
		"""

	@abstractmethod
	def cancel(self, ticket: str) -> None:
		"""Cancel the prompt (teardown). Idempotent -- safe to call twice."""
