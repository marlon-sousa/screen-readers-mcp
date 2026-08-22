# nvdaMcpBridge domain -- the DocumentReader port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: domain port. Answers "what is on this page?" -- the whole flat document
#       the user reads with the cursor keys, rendered as the reader presents it.
# USED BY: the GetDocumentSnapshotHandler.
# IMPLEMENTED BY: adapters/nvda_document_reader.py (NVDA's browse mode);
#                 tests/fakes/document_reader.py FakeDocumentReader.
#
# WHY THIS EXISTS (board entry 11.13, spec 0026). Reading a page line by line
# costs one round trip PER LINE, and that is where the 2026-08-03 run died: it
# reached a results page and never got the three titles. Nothing else in this
# protocol reduces the NUMBER of steps -- spec 0025 made a step cheaper, which is
# a different problem.
#
# WHY IT IS NOT CALLED "BROWSE MODE" OR "VIRTUAL BUFFER". Nothing above the
# bridge learns that NVDA has such a thing. The wire says `document`, the agent
# asks for a document snapshot, and a reader whose flat rendering is called
# something else implements this port and says nothing about the difference. The
# port names the general property: a reader that can hand over its own flat
# document rendering, whole.
#
# THE HONEST LIMIT, and it is the reason `read` may return None. This answers for
# documents and for nothing else. A dialog, a native application, the desktop,
# the system menu -- none has a flat rendering to hand over, and for those the
# agent is back to one keystroke per line. `None` is that answer, and it must
# stay distinguishable from an EMPTY document: a page with nothing on it and a
# focus that is not a page at all send an agent in opposite directions.

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass

from ..entities.document_snapshot import DocumentSnapshot


@dataclass(frozen=True)
class DocumentRead:
	"""What a completed read knows about the document as a whole.

	This port's own DTO, so it lives in this file. Only the title today; it is a
	dataclass rather than a bare `str` return precisely so that a second
	document-level fact can be added without every implementation changing shape
	-- and so that "there is no document" stays expressible as `None` rather than
	as an empty title, which is a real value a real document can have.
	"""

	#: The document's own title, best-effort. Empty when it has none.
	title: str = ""


class DocumentReader(ABC):
	"""Renders the reader's flat document into a snapshot, if there is one."""

	@abstractmethod
	def read(self, snapshot: DocumentSnapshot) -> DocumentRead | None:
		"""Fill *snapshot* with the document's lines; return None if there is none.

		The implementation walks the document in order and calls
		``snapshot.offer(text)`` once per line, stopping when it returns False.
		Every line is offered, including those before ``from_line`` -- the
		snapshot skips, so line ordinals stay absolute.

		An implementation MUST NOT move the user's caret, produce speech, or
		alter the reader's own reading state. This is an observation.
		"""
