# nvdaMcpBridge adapters -- NvdaDocumentReader: the browse buffer, as the user reads it.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the DocumentReader port. On pyright's ignore list
#       (imports NVDA); validated by spec 0026's live-NVDA checklist.
# BUILT BY: adapters/nvda_adapter_factory.py.
# USED BY: the GetDocumentSnapshotHandler.
#
# THE ONE FILE THAT KNOWS WHAT A VIRTUAL BUFFER IS. Everything above it speaks of
# "the document" and of lines of text.
#
# WHY NOT `makeTextInfo(POSITION_ALL).text`, which is the obvious way to get a
# document's text: because it has NO ROLES IN IT. It returns content -- "Skip to
# content", "BlindTec" -- and not a word of "link", "heading level 1" or "radio
# button". Those are not text at all: they are ControlField commands interleaved
# with the text, and the WORDS for them are produced by NVDA's speech layer out
# of the user's own verbosity and document-formatting settings. A snapshot built
# on `.text` would be a different, poorer document than the one the user reads,
# which is the whole thing spec 0026 exists to deliver.
#
# SO WE RENDER THROUGH NVDA'S OWN PRESENTATION PATH. `speech.getTextInfoSpeech`
# is a GENERATOR: it yields the speech sequences `speakTextInfo` would have
# spoken and speaks nothing itself. Per line, with UNIT_LINE and
# OutputReason.CARET, it produces exactly the words the user hears arrowing down
# the document -- under THEIR configuration, which is the only definition of
# "as it appears on the buffer" that means anything.
#
# FOUR PROPERTIES THAT MAKE THIS AN OBSERVATION RATHER THAN AN ACTION:
#
#   1. No synth runs and no speech is emitted. getTextInfoSpeech never calls
#      speak(), so nothing reaches filter_speechSequence (silent mode) or
#      pre_speechQueued (live mode). A snapshot does NOT appear in getSpeech,
#      does not move the speech index, and cannot disturb a waitForSpeech that
#      some other part of the session is running.
#   2. The caret does not move. We walk our OWN TextInfo and never call
#      updateCaret() or updateSelection(). Where the user was before the
#      snapshot is where they are after it. This is the property capturing a
#      say-all could not offer, and it is why the snapshot won that argument.
#   3. The control-field cache is carried across lines, exactly as arrowing
#      does, so a list announces "list with 5 items" ONCE on entry instead of on
#      every line. A fresh state per line would be complete and unrecognisable.
#   4. AND THAT CACHE MUST BE OURS. This is the trap, and it is invisible in
#      review: getTextInfoSpeech calls speakTextInfoState.updateObj() -- writing
#      its cache back onto the document object as `_speakTextInfoState` --
#      UNLESS `useCache` is an explicit SpeakTextInfoState instance
#      (speech/speech.py, _getTextInfoSpeech_updateCache). With the default
#      `useCache=True` a snapshot would leave the user's real browse-mode
#      context pointing at the end of the document, and their next arrow press
#      would announce field boundaries that are not there. Constructing our own
#      state and passing it is the difference between reading the document and
#      altering the reader.
#
# ONE ATOMIC PASS ON NVDA'S MAIN THREAD. The whole walk happens inside a single
# run_on_main(block=True). Not a hop per line: that would let the document change
# under the read, and a snapshot stitched from many instants is exactly what
# `capturedAt` promises it is not. The price is that NVDA's main thread is
# occupied for the render's duration, which is the real cost of "the whole
# document by default" and what spec 0026's checklist item 9 measures.

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

#: A ceiling on how many lines one snapshot will walk, whatever the caller asked
#: for. NOT a default bound -- the default is genuinely the whole document, and
#: spec 0026 rejected a silent cap on the grounds that bounded-by-default means
#: incomplete-by-default. This is a runaway guard, and it guards against exactly
#: one thing: a TextInfo whose `move` keeps reporting progress on a document that
#: is not actually advancing, which would hold NVDA's main thread forever and
#: leave the user's reader wedged. A document longer than this is not truncated
#: by a bound the agent chose, so it reports MAX_LINES like any other cap and the
#: agent can page on from there.
MAX_WALK_LINES: int = 100_000


class NvdaDocumentReader(DocumentReader):
	"""Renders NVDA's browse-mode buffer, line by line, on NVDA's main thread."""

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
				# Report it the way a bound reports itself, rather than returning
				# silently: a snapshot that stopped is never allowed to look complete.
				snapshot.offer("")
				break
			if info.move(textInfos.UNIT_LINE, 1) == 0:
				break

		return DocumentRead(title=_title(interceptor))


def _fresh_state(interceptor: Any) -> Any:
	"""A control-field cache that is OURS and starts EMPTY.

	Two independent requirements, and the constructor gives neither by itself.

	OURS, because `getTextInfoSpeech` calls `speakTextInfoState.updateObj()` --
	writing its cache back onto the document object as `_speakTextInfoState` --
	unless `useCache` is an explicit `SpeakTextInfoState` instance
	(`speech/speech.py`, `_getTextInfoSpeech_updateCache`). Passing our own is
	what stops a snapshot leaving the user's real browse-mode context pointing at
	the end of the document.

	EMPTY, because the constructor SEEDS itself from `obj._speakTextInfoState` --
	the user's live reading position. FOUND LIVE, 2026-08-22: with the caret
	inside a list, a snapshot from the top rendered line 0 as *"fora de lista
	titulo nivel 1 ..."* -- the exit-of-list transition from where the USER was
	welded onto the document's first line. The same page, unchanged, snapshotted
	twice from two caret positions, returned two different texts.

	That is a direct contradiction of what this result claims to be. A snapshot
	says it is the document at an instant; it must not also depend on where the
	person at the keyboard happens to be standing. Clearing the caches renders
	the document as it reads ENTERED FROM THE TOP, which is both what the words
	"the whole document" mean and what NVDA itself produces when a page loads and
	it reads the document out.
	"""
	state = SpeakTextInfoState(interceptor)
	state.controlFieldStackCache = []
	state.formatFieldAttributesCache = {}
	state.indentationCache = ""
	return state


def _browse_document() -> Any:
	"""The focus object's document tree interceptor, or None if there is no document.

	NOT gated on ``passThrough``: focus mode is the user typing INTO a control of
	a document that still exists and still has a rendering, so a snapshot taken
	from inside a form field is a snapshot of that page. The browse/focus
	tri-state is `getState`'s question, not this one.

	``isReady`` is checked because an interceptor that is still building its
	buffer will answer with a partial document, and a partial document that
	reports itself complete is the failure this whole spec is written against.
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
	"""Render one expanded line into the words the reader would speak for it."""
	# GeneratorWithReturn because getTextInfoSpeech is a generator with a RETURN
	# value; iterating it plainly is fine, and this makes that explicit rather
	# than relying on the return being discardable.
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
	"""The document's own title, best-effort -- empty rather than raising."""
	root = getattr(interceptor, "rootNVDAObject", None)
	name = getattr(root, "name", "") if root is not None else ""
	return name if isinstance(name, str) else ""
