# nvdaMcpBridge domain -- BrailleBuffer: indexed capture of what NVDA brailles.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: entity.
# FED BY: the BrailleSource port's implementation, in both capture modes.
# READ BY: the getBraille command handler.

from __future__ import annotations

from typing import Any

from .indexed_buffer import IndexedBuffer


class BrailleBuffer(IndexedBuffer):
	"""NVDA rewrites the whole braille window on every update, so identical consecutive writes are dropped."""

	def _sentinel(self) -> Any:
		return ""

	def _render(self, entry: Any) -> str:
		return entry if isinstance(entry, str) else ""

	def append(self, raw_text: str, log_position: int = 0) -> None:
		text = raw_text.strip()
		if not text:
			return
		with self._lock:
			if self._entries and self._entries[-1] == text:
				return
			self._record(text, log_position)
