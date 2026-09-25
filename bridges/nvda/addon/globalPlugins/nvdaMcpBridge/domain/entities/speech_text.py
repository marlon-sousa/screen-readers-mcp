# nvdaMcpBridge domain -- turning a reader speech sequence into plain text.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: a pure function turning one speech sequence into the string this bridge reports.
# USED BY: the SpeechBuffer and adapters/nvda_document_reader.py, which must agree word for word.

from __future__ import annotations

from typing import Any


def join_speech(sequence: Any) -> str:
	"""Only the ``str`` parts are spoken words; they are joined with a space, because concatenating
	separate fragments runs them together (``Moveindisponivelm``).
	"""
	if not isinstance(sequence, (list, tuple)):
		return ""
	parts = [c.strip() for c in sequence if isinstance(c, str)]  # pyright: ignore[reportUnknownVariableType]
	return " ".join(p for p in parts if p)
