# nvdaMcpBridge tests -- FakeDocumentReader, standing in for the DocumentReader port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# FAKES: domain/ports/document_reader.py
#
# A document a test writes out as a list of lines. It offers them to the snapshot
# in order and stops when told to -- the same protocol the NVDA adapter follows,
# which is what makes the handler tests meaningful: the entity's budgeting is
# exercised through the real call sequence rather than by poking the entity.
#
# `document = None` is the other real answer: not an empty page, but a focus with
# no document rendering at all -- a dialog, the desktop, a native application.

from __future__ import annotations

from collections.abc import Sequence

from nvdaMcpBridge.domain.entities.document_snapshot import DocumentSnapshot
from nvdaMcpBridge.domain.ports.document_reader import DocumentRead, DocumentReader


class FakeDocumentReader(DocumentReader):
	"""A scripted document, offered line by line exactly as the real reader does."""

	def __init__(
		self,
		lines: Sequence[str] | None = None,
		*,
		title: str = "",
		has_document: bool = True,
	) -> None:
		self.lines = list(lines or [])
		self.title = title
		self.has_document = has_document
		#: How many lines were actually rendered, so a test can prove a bound
		#: STOPPED the walk rather than trimming afterwards -- the difference
		#: between a cheap snapshot and an expensive one.
		self.offered = 0

	def read(self, snapshot: DocumentSnapshot) -> DocumentRead | None:
		if not self.has_document:
			return None
		for line in self.lines:
			self.offered += 1
			if not snapshot.offer(line):
				break
		return DocumentRead(title=self.title)
