# nvdaMcpBridge domain -- GetLogHandler: the getLog command.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for ``getLog`` -- returns a filtered, formatted slice of
# NVDA's log for one or more command windows. Anchored by request id; defaults to
# the most recently marked command. Does not mark itself (marks_log = False).
# USES: the LogCapture port (the journal behind it), the Session's command-window
# list through the SessionContext.
#
# Each window is sliced SEPARATELY and the texts joined, rather than slicing one
# span from the first window's start to the last one's end. The windows are
# disjoint but not adjacent -- whatever NVDA logged while the agent was thinking
# between two commands falls between them -- and a single span would swallow that
# idle chatter, which is neither "three commands' worth" nor bounded by anything
# the agent controls.

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

		max_entries = max(0, params.maxEntries)
		texts: list[str] = []
		entries_total = 0
		matched_total = 0
		truncated = False
		for _command_id, start, end, _level in windows:
			# Spend the cap across the windows in order, so an early flood cannot
			# starve the later windows of their `matched` count -- the journal
			# still reports what passed the filters even when nothing fits.
			text, entries, matched, window_truncated = self._slice(
				ctx, start, end, params, max(0, max_entries - entries_total)
			)
			if text:
				texts.append(text)
			entries_total += entries
			matched_total += matched
			truncated = truncated or window_truncated

		return protocol.LogSliceResult(
			text="\n".join(texts),
			entries=entries_total,
			matched=matched_total,
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
