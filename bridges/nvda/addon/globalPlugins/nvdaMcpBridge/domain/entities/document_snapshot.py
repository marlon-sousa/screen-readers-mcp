# nvdaMcpBridge domain -- DocumentSnapshot: the document being read, as it fills.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: entity. The accumulating snapshot of a browse document (spec 0026), and
#       the one place that decides WHERE A READ STOPS AND WHY.
# FILLED BY: the DocumentReader port's implementation, which offers it one
#            rendered line at a time and stops when told to.
# BUILT BY: the GetDocumentSnapshotHandler, from the request's parameters.
# DEPENDS ON: nothing. Pure -- no ports, no clock, no IO.
#
# WHY THE BUDGET LIVES HERE AND NOT IN THE ADAPTER. "Which bound bit" is
# arithmetic with three genuinely confusable outcomes, one of which is a
# coincidence -- a document that ENDS exactly on a bound was not truncated, and
# calling it truncated would send an agent back for a page that does not exist.
# In the adapter that logic would sit behind a live NVDA and be untestable; here
# it is a handful of pure assertions. The adapter is left with no decision at
# all: render a line, offer it, stop when offer says stop.
#
# WHY A LINE IS OFFERED RATHER THAN RETURNED. The alternative -- the adapter
# hands over every line and the entity trims -- would render a thousand lines to
# keep ten, inside a call that occupies NVDA's main thread for its whole
# duration. `offer` returning False is the entity telling the adapter it may
# stop walking, which is the only way a bound saves any work.

from __future__ import annotations

from ... import protocol


class DocumentSnapshot:
	"""The lines collected so far, the bounds in force, and why collection ended."""

	def __init__(self, from_line: int = 0, max_lines: int = 0, max_chars: int = 0) -> None:
		"""Bounds as the wire states them: ``0`` means NO limit, for both caps.

		The unbounded call is the ordinary one. Negative values are clamped to 0
		rather than rejected -- there is no useful reading of "minus three lines",
		and a validation error on a bound would fail a call whose whole intent was
		"give me everything".
		"""
		self._from_line = max(0, from_line)
		self._max_lines = max(0, max_lines)
		self._max_chars = max(0, max_chars)
		self._lines: list[protocol.SnapshotLine] = []
		self._chars = 0
		self._next_line = 0
		self._truncated_by = protocol.TruncatedBy.NONE

	@property
	def from_line(self) -> int:
		"""The first line the caller asked for."""
		return self._from_line

	@property
	def lines(self) -> list[protocol.SnapshotLine]:
		"""The collected lines, in document order, with ABSOLUTE ordinals."""
		return list(self._lines)

	@property
	def to_line(self) -> int:
		"""One past the last line collected, so ``[from_line, to_line)`` is the span."""
		return self._lines[-1].line + 1 if self._lines else self._from_line

	@property
	def truncated_by(self) -> protocol.TruncatedBy:
		"""Which bound stopped the read, or ``NONE`` if none did."""
		return self._truncated_by

	def offer(self, text: str) -> bool:
		"""Offer the next line of the document; return False when collection is over.

		The caller walks the document in order and calls this once per line,
		INCLUDING the lines before ``from_line`` -- skipping is this entity's job,
		because it is what keeps the reported ordinals absolute without the adapter
		doing arithmetic. A False return means "stop walking"; the caller must not
		call again after one.
		"""
		line = self._next_line
		self._next_line += 1
		if line < self._from_line:
			return True

		if self._max_lines and len(self._lines) >= self._max_lines:
			self._truncated_by = protocol.TruncatedBy.MAX_LINES
			return False
		# The FIRST line is always taken, however small the character budget.
		# Returning nothing here would be indistinguishable from an empty
		# document, which is a different and much worse answer than a short one.
		if self._max_chars and self._lines and self._chars + len(text) > self._max_chars:
			self._truncated_by = protocol.TruncatedBy.MAX_CHARS
			return False

		self._lines.append(protocol.SnapshotLine(line=line, text=text))
		self._chars += len(text)
		# Exhausting a bound is not the same as being cut off BY it: a document
		# that ends on the last line the budget allowed was rendered whole, and
		# says so on the next `offer` that never comes.
		return True
