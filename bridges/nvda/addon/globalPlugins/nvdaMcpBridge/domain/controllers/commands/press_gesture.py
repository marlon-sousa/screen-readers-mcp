# nvdaMcpBridge domain -- PressGestureHandler: inject keyboard gestures in order.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `pressGesture`, reporting the speech each gesture caused in its grace window.
# An unresolvable id raises GestureError, aborting the remaining gestures; the session survives.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandHandler
from .observation import speech_entries, state_snapshot

if TYPE_CHECKING:
	from .session_context import SessionContext


class PressGestureHandler(CommandHandler):
	mutates_reader = True

	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		params = protocol.from_dict(protocol.PressGestureParams, request.params)
		grace = max(0, params.graceMs) / 1000.0
		buffer = ctx.speech_buffer

		# Announced before anything is dispatched, so a muted tester hears what is about to happen.
		if params.announce.strip():
			ctx.announce_to_human(params.announce)

		start_index = buffer.next_index()
		presses: list[protocol.GesturePress] = []
		for gesture_id in params.gestures:
			# Taken before dispatch, so an empty span means the key said nothing.
			press_from = buffer.next_index()
			ctx.transcript.gesture(gesture_id)
			ctx.adapter_set.gesture_sender.press(gesture_id)
			buffer.collect_since(press_from, grace)
			presses.append(
				protocol.GesturePress(
					gesture=gesture_id,
					speechFrom=press_from,
					speechTo=buffer.next_index(),
				)
			)

		entries, from_index, to_index = buffer.entries_since(start_index)
		return protocol.GestureResult(
			pressed=presses,
			speech=speech_entries(entries),
			speechFrom=from_index,
			speechTo=to_index,
			# Mode-state only: focus moves asynchronously, so a sample now could report the page just left.
			state=state_snapshot(ctx),
		)
