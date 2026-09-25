# nvdaMcpBridge tests -- FakeUserPrompter, standing in for the UserPrompter port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from nvdaMcpBridge.domain.ports.user_prompter import UserPrompter


class FakeUserPrompter(UserPrompter):
	def __init__(self) -> None:
		self.presented: list[tuple[str, str]] = []
		self.cancelled: list[str] = []

	def present(self, prompt: str, ticket: str) -> None:
		self.presented.append((prompt, ticket))

	def cancel(self, ticket: str) -> None:
		self.cancelled.append(ticket)
