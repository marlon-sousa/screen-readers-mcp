# nvdaMcpBridge domain -- the UserPrompter port: ask the human and acknowledge.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port; presents a prompt to the human audibly and cancels it.
# USED BY: AskUserHandler and teardown.
# IMPLEMENTED BY: adapters/nvda_user_prompter.py and tests/fakes/user_prompter.py.

from __future__ import annotations

from abc import ABC, abstractmethod


class UserPrompter(ABC):
	@abstractmethod
	def present(self, prompt: str, ticket: str) -> None:
		"""Called from the session thread; the implementation must marshal to the main thread."""

	@abstractmethod
	def cancel(self, ticket: str) -> None:
		"""Cancel the prompt; must be safe to call twice."""
