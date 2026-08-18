# nvdaMcpBridge domain -- observation: what a command reports having seen.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: supporting construct -- two pure mappings from what the entities hold to
# what the wire publishes. No state, no IO of its own; it is functions, not a
# class, because there is nothing to hold.
#
# It exists because spec 0025 gives THREE commands the same two answers to
# assemble. getSpeech and pressGesture/typeText now all report captured
# utterances, and getState and pressGesture/typeText all report the reader's
# mode-state. Written out five times, the wallclock formatting or the BrowseMode
# widening would be corrected in four places and missed in the fifth -- which is
# exactly the failure spec 0028 recorded when three append() implementations each
# grew the same field by hand.
#
# LAYOUT AMENDMENT to spec 0025 (AGENTS.md: an amendment rides in the PR with a
# one-line why): the spec's table names the two controllers and the buffer, and
# does not mention this module. The why is the paragraph above -- the duplication
# is across commands, so the remedy cannot live inside either one of them.

from __future__ import annotations

from typing import TYPE_CHECKING

from .... import protocol
from .wallclock import format_wallclock

if TYPE_CHECKING:
	from .session_context import SessionContext


def speech_entries(entries: list[tuple[str, int, int, float]]) -> list[protocol.SpeechEntry]:
	"""Map the buffer's tuples to wire entries, formatting the capture stamp.

	The tuple is ``(text, index, logPosition, emittedAt)`` -- the entity stores
	the stamp as a NUMBER and this is the presentation step (spec 0028), which is
	the reason the entity never learned the format.
	"""
	return [
		protocol.SpeechEntry(
			text=text,
			index=index,
			logPosition=log_position,
			emittedAt=format_wallclock(emitted_at),
		)
		for text, index, log_position, emitted_at in entries
	]


def state_snapshot(ctx: SessionContext) -> protocol.StateResult:
	"""Sample the reader's mode-state through the StateInspector port.

	The port speaks the same three strings the wire does, so ``BrowseMode`` is a
	widening into the closed set -- and it RAISES on anything else, which is the
	point: a bridge that invented a fourth mode should fail here rather than put
	an unknown string on the wire.
	"""
	state = ctx.adapter_set.state_inspector.state()
	return protocol.StateResult(
		browseMode=protocol.BrowseMode(state.browse_mode),
		speechMode=state.speech_mode,
		sleepMode=state.sleep_mode,
		inputHelp=state.input_help,
	)
