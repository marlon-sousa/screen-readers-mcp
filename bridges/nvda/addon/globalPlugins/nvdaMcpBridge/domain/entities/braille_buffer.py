# nvdaMcpBridge domain -- BrailleBuffer: indexed capture of what NVDA brailles.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: entity.
# FED BY: the SpeechSource port's implementation (NVDA's braille.pre_writeCells
#         hook, in both capture modes) calling append.
# READ BY: the Session controller, answering getBraille.
# DEPENDS ON: the Clock port (injected via IndexedBuffer).

from __future__ import annotations

from typing import Any

from .indexed_buffer import IndexedBuffer


class BrailleBuffer(IndexedBuffer):
	"""Indexed capture of raw braille text, de-duplicating consecutive repeats.

	NVDA rewrites the whole braille window on every update; identical
	consecutive writes are dropped (as NVDASpyLib does) so the buffer records
	genuine changes rather than refreshes.
	"""

	def _sentinel(self) -> Any:
		return ""

	def _render(self, entry: Any) -> str:
		return entry if isinstance(entry, str) else ""

	def append(self, raw_text: str, log_position: int = 0) -> None:
		"""Record a braille update; empty or unchanged text is ignored.

		``log_position`` is the journal's append position at the moment of
		capture (spec 0021), handed in by the caller as a plain value -- this
		buffer never learns the journal exists.
		"""
		text = raw_text.strip()
		if not text:
			return
		with self._lock:
			if self._entries and self._entries[-1] == text:
				return
			self._entries.append(text)
			self._log_positions.append(log_position)
			self._last_time = self._clock.monotonic()
