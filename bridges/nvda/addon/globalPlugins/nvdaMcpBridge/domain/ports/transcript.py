# nvdaMcpBridge domain -- the Transcript port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port; the human-readable record of everything a session did.
# USED BY: the Session controller.
# IMPLEMENTED BY: adapters/file_transcript.py and tests/fakes/transcript.py.

from __future__ import annotations

from abc import ABC, abstractmethod


class Transcript(ABC):
	@property
	@abstractmethod
	def path(self) -> str:
		pass

	@abstractmethod
	def open(self) -> None: ...

	@abstractmethod
	def session_opened(self, mode: str, synth: str, persona: str) -> None:
		"""persona is empty when the server declared none."""

	@abstractmethod
	def gesture(self, gesture_id: str) -> None: ...

	@abstractmethod
	def typed(self, length: int) -> None:
		"""Record only the length: the typed text may be a secret and must never reach disk."""

	@abstractmethod
	def speech(self, text: str) -> None: ...

	@abstractmethod
	def note(self, text: str) -> None: ...

	@abstractmethod
	def session_closed(self, reason: str) -> None: ...
