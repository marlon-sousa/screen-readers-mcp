# nvdaMcpBridge domain -- rendering a wall-clock stamp for the wire.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: a pure function, not a class. No state, no collaborators, no IO -- it
#       turns an epoch float into the one string shape this protocol uses.
# USED BY: get_log_position (the `time` field) and the four speech/braille reads
#          (the `emittedAt` field). Extracted here by spec 0028 precisely so
#          those two renderings cannot drift into two formats.
#
# WHY THIS FORMAT: it is what `FileTranscript` already writes and what NVDA's own
# log records look like, so a stamp an agent reads back can be pasted straight
# into a search of nvda.log or of the session transcript. Half the value of
# reporting a wall clock at all is joining artefacts stamped by somebody else;
# a format of our own invention would forfeit it.

from __future__ import annotations

from datetime import datetime

#: Milliseconds, not microseconds. `%f` renders six digits and the last three
#: are noise at the resolution anything here is measured to, so they are cut.
_MICROSECONDS_TO_MILLISECONDS = -3


def format_wallclock(epoch: float) -> str:
	"""Render epoch seconds as ``YYYY-MM-DD HH:MM:SS.mmm``.

	``0.0`` renders as the **empty string** rather than as 1970. Zero is the
	buffers' sentinel value -- the seeded entry at index 0, and the answer for an
	out-of-range index -- and it means *no instant was recorded*, which an empty
	string says and a date fifty years ago actively misleads about (spec 0028).
	"""
	if not epoch:
		return ""
	return datetime.fromtimestamp(epoch).strftime("%Y-%m-%d %H:%M:%S.%f")[:_MICROSECONDS_TO_MILLISECONDS]
