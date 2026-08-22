# nvdaMcpBridge domain -- turning a reader speech sequence into plain text.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: a pure function, not a class. No state, no collaborators, no IO -- it
#       turns one speech sequence into the one string shape this bridge reports.
# USED BY: the SpeechBuffer (capture) and adapters/nvda_document_reader.py (the
#          document snapshot, spec 0026).
#
# WHY IT LIVES HERE RATHER THAN INSIDE THE BUFFER. It was private to
# `speech_buffer.py` until the document snapshot needed the identical rule, and
# the two must not drift: a snapshot line and a captured utterance are compared
# WORD FOR WORD by the live checklist, which is how we find out whether the
# snapshot really renders what the reader would say. Two copies of a join rule
# is a difference waiting to be discovered as a false finding. Extracted for
# exactly the reason spec 0028 extracted `format_wallclock`.
#
# Note this is a DOMAIN module that takes an NVDA speech sequence as `Any`. That
# is the established shape here -- `SpeechBuffer.append` has always done it --
# and it stays honest because the sequence is treated as an opaque iterable of
# items of which only `str` matters. Nothing here imports NVDA or knows what any
# other item in the sequence is.

from __future__ import annotations

from typing import Any


def join_speech(sequence: Any) -> str:
	"""Join the plain-string parts of a speech sequence with a separating space.

	NVDA speech sequences interleave ``str`` fragments with ``SpeechCommand``
	objects (pitch, index, callbacks, ...). Only the strings are spoken words,
	so those are all we capture.

	The parts are joined with a SPACE, not concatenated. A sequence's fragments
	are separate utterances -- a name, a role, a position, an accelerator letter
	-- and running them together produces text no reader can segment:
	``"Move" + "indisponivel" + "m"`` came out as ``Moveindisponivelm``, and
	``"Google Chrome" + "17 de 37"`` as ``Google Chrome17 de 37``. The join is
	the only place the boundary is known, so it is the only place it can be kept.
	"""
	if not isinstance(sequence, (list, tuple)):
		return ""
	parts = [c.strip() for c in sequence if isinstance(c, str)]  # pyright: ignore[reportUnknownVariableType]
	return " ".join(p for p in parts if p)
