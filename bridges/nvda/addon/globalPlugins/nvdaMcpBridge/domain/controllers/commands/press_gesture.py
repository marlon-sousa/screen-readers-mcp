# nvdaMcpBridge domain -- PressGestureHandler: inject keyboard gestures in order.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `pressGesture`. Logs then presses each gesture in
# order, blocking until NVDA processed each, waits a GRACE WINDOW for the speech
# each one caused, and reports what arrived. The first unresolvable id raises
# GestureError, which aborts the remainder; the Session turns that into an error
# Response (naming the id) and the session survives -- so error-wrapping stays in
# the dispatcher, not here.
#
# MUTATES_READER = True: a keypress moves the user's machine, so an observe-only
# session (spec 0017) refuses this handler. This is the ORIGINAL mutating
# command -- the one spec 0019 argued typeText was "as surely" a mutation as.
#
# WHY IT OBSERVES AT ALL (spec 0025). The agent's loop used to be three round
# trips -- act, settle, listen -- costing ~7.9 s to carry ~124 ms of reader work,
# and the middle one was measured to observe nothing whatsoever. Waiting here
# instead costs ~4% of a trip the caller is already paying. The result says what
# had arrived by a stated instant and where to resume; it NEVER says that is all
# there is, which is why nothing here computes a `complete` flag.

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

		# Spoken BEFORE anything is dispatched, so a mute tester hears what is
		# about to happen to their machine rather than what just did (spec 0025
		# Part 3.4). Whitespace is not an announcement.
		if params.announce.strip():
			ctx.announce_to_human(params.announce)

		start_index = buffer.next_index()
		presses: list[protocol.GesturePress] = []
		for gesture_id in params.gestures:
			# The bookmark is taken BEFORE dispatch: it is the coordinate the
			# ring stood at when this key went out, which is what makes an empty
			# span mean "this key said nothing" rather than "we looked too late".
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

		# Re-read the whole window rather than concatenating the per-gesture
		# collections: the ring is the single source of what was said, and one
		# read of it cannot disagree with itself the way N appended slices could.
		entries, from_index, to_index = buffer.entries_since(start_index)
		return protocol.GestureResult(
			pressed=presses,
			speech=speech_entries(entries),
			speechFrom=from_index,
			speechTo=to_index,
			# Sampled at the CLOSE of the last grace window -- an instant the
			# caller knows. Mode-state only, never focus: a browse/focus toggle
			# is synchronous with the script that performed it and is already
			# complete here, while focus movement is asynchronous and a sample
			# taken now would report the document you left, confidently and
			# wrongly (spec 0023, upheld by 0025 Part 3.3).
			state=state_snapshot(ctx),
		)
