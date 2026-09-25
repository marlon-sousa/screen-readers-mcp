# nvdaMcpBridge domain -- DocumentSnapshot: the document being read, as it fills.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: entity, the accumulating snapshot of a browse document, deciding where a read stops.
# FILLED BY: the DocumentReader port's implementation, one line at a time.
# BUILT BY: the GetDocumentSnapshotHandler, from the request's parameters.

from __future__ import annotations

from ... import protocol


class DocumentSnapshot:
	def __init__(self, from_line: int = 0, max_lines: int = 0, max_chars: int = 0) -> None:
		"""``0`` means no limit for both caps; negative values are clamped to 0."""
		self._from_line = max(0, from_line)
		self._max_lines = max(0, max_lines)
		self._max_chars = max(0, max_chars)
		self._lines: list[protocol.SnapshotLine] = []
		self._chars = 0
		self._next_line = 0
		self._truncated_by = protocol.TruncatedBy.NONE

	@property
	def from_line(self) -> int:
		return self._from_line

	@property
	def lines(self) -> list[protocol.SnapshotLine]:
		"""Ordinals are absolute, counted from the start of the document."""
		return list(self._lines)

	@property
	def to_line(self) -> int:
		return self._lines[-1].line + 1 if self._lines else self._from_line

	@property
	def truncated_by(self) -> protocol.TruncatedBy:
		return self._truncated_by

	def offer(self, text: str) -> bool:
		"""Offer every line in order, including those before ``from_line``; stop walking on False."""
		line = self._next_line
		self._next_line += 1
		if line < self._from_line:
			return True

		if self._max_lines and len(self._lines) >= self._max_lines:
			self._truncated_by = protocol.TruncatedBy.MAX_LINES
			return False
		# The first line is always taken, or a tiny budget would read as an empty document.
		if self._max_chars and self._lines and self._chars + len(text) > self._max_chars:
			self._truncated_by = protocol.TruncatedBy.MAX_CHARS
			return False

		self._lines.append(protocol.SnapshotLine(line=line, text=text))
		self._chars += len(text)
		# A document that ends exactly on a bound was not truncated by it.
		return True
