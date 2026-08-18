# nvdaMcpBridge domain -- the ContinuousRead port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: domain port. Answers "is the reader part-way through a continuous read?"
#       -- one command that goes on producing speech, chunk after chunk, long
#       after the keystroke that started it returned.
# USED BY: the SpeechBuffer, deciding whether speech has finished.
# IMPLEMENTED BY: adapters/nvda_continuous_read.py (NVDA's say all);
#                 tests/fakes/continuous_read.py FakeContinuousRead.
#
# WHY THIS EXISTS (board entry 11.21). "Has speech finished?" is answered by a
# heuristic: nothing new for a second. That is sound for a keystroke, whose
# speech arrives in one burst. It is wrong for a continuous read, because NVDA
# produces one CHUNK at a time and asks for the next only when the synth reports
# it has reached the previous one -- so between two chunks, production is paused
# on audio, and the buffer sees exactly what it sees when a read is over. The
# tool reported `finished: true` against a say all the user could plainly hear
# continuing, and an agent that believed it would read a fraction of the document
# and move on.
#
# The heuristic cannot be fixed, because the two states are identical from
# outside: silence-because-done and silence-because-waiting look the same. What
# CAN be done is to stop inferring where the reader already knows. NVDA tracks
# its say all -- so the bridge asks.
#
# WHY THE PORT IS NOT CALLED "SAY ALL". Nothing above the bridge learns that NVDA
# has such a command. There is no say-all tool, no say-all parameter, nothing on
# the wire that names it: an agent starts one by pressing the reader's own key,
# exactly as a user would, and that is all the MCP ever knows about it. What
# changes is only the ANSWER to a question the wire already asks. So the port is
# named for the general property -- a read that continues under its own power --
# and a bridge for a reader that has no such notion, or no way to see it,
# implements this as `False` and keeps the heuristic it has today.
#
# THE HONEST LIMIT. This closes the gap for continuous reads and nothing else. A
# different bursty producer would fool the heuristic in exactly the same way, and
# the bridge would not know. We are not claiming to answer "will more speech
# arrive?" in general -- that question has no answer from outside. We are
# declining to guess in the one case where the reader can be asked.

from __future__ import annotations

from abc import ABC, abstractmethod


class ContinuousRead(ABC):
	"""Answers "is a self-advancing read in progress right now?"."""

	@abstractmethod
	def in_progress(self) -> bool:
		"""True while a continuous read is running, including between chunks."""
