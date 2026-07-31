# nvdaMcpBridge domain -- GetLogHandler: the getLog command.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for ``getLog`` -- returns a filtered, formatted slice of
# NVDA's log for one or more command windows. Anchored by request id; defaults to
# the most recently marked command. Does not mark itself (marks_log = False).
# USES: the LogCapture port (the journal behind it), the Session's command-window
# list through the SessionContext.
#
# A multi-window request is ONE span, from the first window's start to the last
# one's end -- the gaps between the windows included.
#
# Slicing each window separately and joining reads better on paper, and it was
# tried: it is more precise, and it keeps the idle chatter from between two
# commands out of the answer. Live NVDA killed it. A command's window closes the
# moment the handler returns, but NVDA does the WORK the command caused just
# after that, on its own thread:
#
#     IO - inputCore.executeGesture (18:47:56.033)   <- inside the window
#     IO - speech.speech.speak      (18:47:56.034)   <- one millisecond later
#
# The speech record -- the one an agent asking "what did that keypress do?"
# actually wants -- lands a millisecond past the end mark, in the gap. Excluding
# gaps therefore excludes most of what the feature exists to show, so the span
# wins: an agent that asked for three windows gets everything between the start
# of the first and the end of the last, idle chatter included, bounded by
# maxEntries like everything else.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandError, CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class GetLogHandler(CommandHandler):
	"""Return a filtered, formatted slice of the NVDA log journal."""

	marks_log = False

	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		params = protocol.from_dict(protocol.GetLogParams, request.params)

		# Resolve the anchor: the named command, or the most recently marked one.
		if params.commandId is not None:
			window_index = ctx.command_window_index(params.commandId)
			if window_index is None:
				raise CommandError(
					f"command id {params.commandId} not found among the last "
					f"{len(ctx.command_windows)} marked commands"
				)
		else:
			if not ctx.command_windows:
				raise CommandError("no commands have been marked yet")
			window_index = -1  # most recent

		windows = ctx.command_windows_for(window_index, max(1, params.windows))
		if not windows:
			raise CommandError("no command windows within range")

		text, entries, matched, truncated = self._slice(
			ctx, windows[0][1], windows[-1][2], params, max(0, params.maxEntries)
		)

		return protocol.LogSliceResult(
			text=text,
			entries=entries,
			matched=matched,
			truncated=truncated,
			fromCommandId=windows[0][0],
			toCommandId=windows[-1][0],
			# The floor in force when the OLDEST window in the range was recorded.
			# If setLogLevel ran mid-range the later windows saw more than this
			# says, which is the safe direction: it never claims to have captured
			# something it did not.
			capturedAtLevel=windows[0][3],
		)

	@staticmethod
	def _slice(
		ctx: SessionContext,
		start: int,
		end: int,
		params: protocol.GetLogParams,
		max_entries: int,
	) -> tuple[str, int, int, bool]:
		"""One window's slice, with the journal's rejections reported as command errors."""
		try:
			return ctx.log_capture.slice(
				start,
				end,
				min_level=params.minLevel,
				contains=params.contains,
				exclude=params.exclude,
				fields=params.fields,
				max_entries=max_entries,
			)
		except ValueError as exc:
			# An unknown field name or level: the agent's parameters, not a fault.
			raise CommandError(str(exc)) from None
