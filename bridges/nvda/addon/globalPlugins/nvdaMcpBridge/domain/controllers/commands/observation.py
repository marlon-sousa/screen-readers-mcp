# nvdaMcpBridge domain -- observation: what a command reports having seen.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: supporting construct, the pure mappings from entity state to wire results shared by several commands.

from __future__ import annotations

from typing import TYPE_CHECKING

from .... import protocol
from .wallclock import format_wallclock

if TYPE_CHECKING:
	from .session_context import SessionContext


def speech_entries(entries: list[tuple[str, int, int, float]]) -> list[protocol.SpeechEntry]:
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
	"""Raises on a browse mode outside the wire's closed set rather than publishing it."""
	state = ctx.adapter_set.state_inspector.state()
	return protocol.StateResult(
		browseMode=protocol.BrowseMode(state.browse_mode),
		speechMode=state.speech_mode,
		sleepMode=state.sleep_mode,
		inputHelp=state.input_help,
	)
