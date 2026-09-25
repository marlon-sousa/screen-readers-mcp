# nvdaMcpBridge domain -- the DocumentReader port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port, handing over the reader's whole flat document rendering.
# USED BY: the GetDocumentSnapshotHandler.
# IMPLEMENTED BY: adapters/nvda_document_reader.py; tests/fakes/document_reader.py.

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass

from ..entities.document_snapshot import DocumentSnapshot


@dataclass(frozen=True)
class DocumentRead:
	"""No document is ``None``, never an empty title: an empty title is a real value."""

	# Best-effort; empty when the document has none.
	title: str = ""


class DocumentReader(ABC):
	@abstractmethod
	def read(self, snapshot: DocumentSnapshot) -> DocumentRead | None:
		"""Offer every line to ``snapshot.offer``; None, distinct from empty, means no document.

		Must not move the caret, speak, or alter the reader's reading state.
		"""
