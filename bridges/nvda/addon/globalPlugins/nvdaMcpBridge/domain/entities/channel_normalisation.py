# nvdaMcpBridge domain -- the admitted channel-shift settings (spec 0024).
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: entity. THE SET AS DATA, plus the one rule that decides membership.
# USED BY: the HelloHandler, which applies it through the ConfigAccessor.
#
# THE MEMBERSHIP TEST, and it is the whole of this file's reason to exist:
#
#   A session may change a setting only if the change MOVES INFORMATION BETWEEN
#   CHANNELS WITHOUT ADDING OR REMOVING ANY.
#
# Such a change cannot alter what the reader DECIDED to report -- only where the
# report is delivered. The event, its timing and its content are identical; the
# agent's copy stops being empty. A change that alters what the reader would have
# said is a change to the thing under test and is refused however convenient it
# would be: spec 0023's stance is that the agent simulates a USER, and a session
# that rewrites the reader's configuration makes every finding afterwards carry
# an asterisk.
#
# WHY IT IS A LIST OF ONE. `progressBarOutputMode` passes the test and is still
# not here: no run has been blocked by it, and every admitted key is a small tax
# on fidelity. The set is DATA precisely so the next key is a line plus a test to
# argue against, rather than a new shape. Ship the key that cost a session; let
# the next one be admitted by the run that needs it.
#
# The `why` strings are FIXED and owned here, never composed at runtime and never
# translated. They ride to the agent and into the transcript, which is read by
# humans who will not have the spec open; a reason that could drift from the spec
# would be worse than none.

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class AdmittedSetting:
	"""One setting the membership test admits, and the value that shifts it."""

	#: The reader's own config path, outermost key first.
	key_path: tuple[str, ...]
	#: What the session writes to move the signal into the speech channel.
	value: Any
	#: Why this key is admitted, in one line, for the human reading the record.
	why: str


#: Every setting a session may normalise today. NVDA's browse/focus mode change
#: is a wave file (`focusMode.wav` / `browseMode.wav`) unless this key is off, in
#: which case NVDA SPEAKS "Focus mode" / "Browse mode" instead -- same event,
#: same instant, same information, a different channel. It is the key that cost
#: the 2026-08-03 session: the human heard the tone and knew instantly, the agent
#: read only words and could not tell "no headings here" from "the keys went
#: somewhere else".
ADMITTED_SETTINGS: tuple[AdmittedSetting, ...] = (
	AdmittedSetting(
		key_path=("virtualBuffers", "passThroughAudioIndication"),
		value=False,
		why="browse/focus mode changes are a wave file by default",
	),
)
