# nvdaMcpBridge adapters -- NvdaDocumentReader: the browse buffer, as the user reads it.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing DocumentReader: renders the browse-mode buffer as the user would hear it.
# BUILT BY: adapters/nvda_adapter_factory.py.
# USED BY: the GetDocumentSnapshotHandler.
# Each line goes through speech.getTextInfoSpeech, so roles and field words come out under the user's own
# settings; makeTextInfo(...).text carries none of them. getTextInfoSpeech speaks nothing, so a snapshot
# never reaches the speech buffer, and the walk never moves the caret.
# The whole walk is one run_on_main pass, so the document cannot change under it; NVDA's main thread is
# busy for its duration.

from __future__ import annotations

from typing import Any

import api
import textInfos
import treeInterceptorHandler
from controlTypes import OutputReason
from speech.speech import SpeakTextInfoState, getTextInfoSpeech
from speech.types import GeneratorWithReturn

from ..domain.entities.document_snapshot import DocumentSnapshot
from ..domain.entities.speech_text import join_speech
from ..domain.ports.document_reader import DocumentRead, DocumentReader
from .nvda_main_thread import run_on_main

#: A runaway guard against a TextInfo whose move keeps reporting progress, which would hold NVDA's
#: main thread forever; it is not a default bound.
MAX_WALK_LINES: int = 100_000


class NvdaDocumentReader(DocumentReader):
	def read(self, snapshot: DocumentSnapshot) -> DocumentRead | None:
		return run_on_main(lambda: self._read(snapshot), block=True)

	@staticmethod
	def _read(snapshot: DocumentSnapshot) -> DocumentRead | None:
		interceptor = _browse_document()
		if interceptor is None:
			return None

		info = interceptor.makeTextInfo(textInfos.POSITION_FIRST)
		state = _fresh_state(interceptor)
		walked = 0
		while True:
			line = info.copy()
			line.expand(textInfos.UNIT_LINE)
			if not snapshot.offer(_render(line, state)):
				break
			walked += 1
			if walked >= MAX_WALK_LINES:
				# A snapshot that stopped must never look complete.
				snapshot.offer("")
				break
			if info.move(textInfos.UNIT_LINE, 1) == 0:
				break

		return DocumentRead(title=_title(interceptor))


def _fresh_state(interceptor: Any) -> Any:
	"""A control-field cache that is ours and starts empty.

	Ours, because getTextInfoSpeech writes its cache back onto the document object unless useCache is an
	explicit SpeakTextInfoState, which would corrupt the user's browse-mode context.
	Empty, because in NVDA 2026.1 the constructor seeds itself from the user's live reading position,
	which welds their current context onto the document's first line.
	"""
	state = SpeakTextInfoState(interceptor)
	state.controlFieldStackCache = []
	state.formatFieldAttributesCache = {}
	state.indentationCache = ""
	return state


def _browse_document() -> Any:
	"""None when there is no ready document; focus mode still counts as a document.

	An interceptor that is not yet ready answers with a partial document.
	"""
	focus = api.getFocusObject()
	if focus is None:
		return None
	interceptor = getattr(focus, "treeInterceptor", None)
	if not isinstance(interceptor, treeInterceptorHandler.DocumentTreeInterceptor):
		return None
	if not getattr(interceptor, "isReady", False):
		return None
	return interceptor


def _render(line: Any, state: Any) -> str:
	sequences = GeneratorWithReturn(
		getTextInfoSpeech(
			line,
			useCache=state,
			unit=textInfos.UNIT_LINE,
			reason=OutputReason.CARET,
		)
	)
	parts = [join_speech(sequence) for sequence in sequences]
	return " ".join(part for part in parts if part)


def _title(interceptor: Any) -> str:
	root = getattr(interceptor, "rootNVDAObject", None)
	name = getattr(root, "name", "") if root is not None else ""
	return name if isinstance(name, str) else ""
