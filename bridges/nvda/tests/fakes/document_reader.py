# nvdaMcpBridge tests -- FakeDocumentReader, standing in for the DocumentReader port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# has_document=False stands for a focus with no document at all, not an empty page.

from __future__ import annotations

from collections.abc import Sequence

from nvdaMcpBridge.domain.entities.document_snapshot import DocumentSnapshot
from nvdaMcpBridge.domain.ports.document_reader import DocumentRead, DocumentReader


class FakeDocumentReader(DocumentReader):
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
		#: Lines actually rendered, so a test can prove a bound stopped the walk.
		self.offered = 0

	def read(self, snapshot: DocumentSnapshot) -> DocumentRead | None:
		if not self.has_document:
			return None
		for line in self.lines:
			self.offered += 1
			if not snapshot.offer(line):
				break
		return DocumentRead(title=self.title)
