# nvdaMcpBridge domain -- the Transcript port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from abc import ABC, abstractmethod


class Transcript(ABC):
	"""A per-session, line-flushed transcript of everything that happened.

	Written bridge-side (complete even if the agent never fetched some speech)
	and flushed per line (a crash loses nothing). ``path`` is returned to the
	agent at ``hello`` so the server can surface it. The file-backed
	implementation lives in ``adapters/file_transcript.py``.
	"""

	@property
	@abstractmethod
	def path(self) -> str: ...

	@abstractmethod
	def open(self) -> None: ...

	@abstractmethod
	def session_opened(self, mode: str, synth: str) -> None: ...

	@abstractmethod
	def synth_swapped(self, real_synth: str) -> None: ...

	@abstractmethod
	def synth_restored(self, real_synth: str) -> None: ...

	@abstractmethod
	def gesture(self, gesture_id: str) -> None: ...

	@abstractmethod
	def speech(self, text: str) -> None: ...

	@abstractmethod
	def note(self, text: str) -> None: ...

	@abstractmethod
	def session_closed(self, reason: str) -> None: ...
