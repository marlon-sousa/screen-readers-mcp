# nvdaMcpBridge domain -- GetLogHandler: the getLog command.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for ``getLog`` -- returns a filtered, formatted slice of
# NVDA's log, anchored one of three mutually exclusive ways (spec 0021):
# ``sincePosition`` (a caller-held cursor -- reads never consume it),
# ``lastSeconds`` (relative to now, for "it just happened" with no prior mark),
# or ``commandId``/``windows`` (0020's original command-window anchor, still the
# default when neither of the above is given). Does not mark itself
# (marks_log = False), so it can never become its own default anchor.
#
# Every result also carries ``nextPosition`` -- the journal's current position,
# to pass back as ``sincePosition`` and continue the tail without re-reading or
# skipping anything.
#
# A multi-window request (the commandId/windows anchor) is ONE span, from the
# first window's start to the last one's end -- the gaps between the windows
# included.
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
# maxEntries like everything else. Under 0021's span model (a window runs to the
# NEXT marking command) there is no longer a gap to exclude at all -- spans are
# adjacent by construction -- but the span-not-concatenate choice is unchanged.

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
		self._check_one_anchor(params)

		if params.sincePosition is not None:
			text, entries, matched, truncated = self._call(
				ctx.log_capture.slice_since, params.sincePosition, params
			)
			from_command_id: int | None = None
			to_command_id: int | None = None
			captured_at_level = ctx.log_capture.current_level
		elif params.lastSeconds is not None:
			text, entries, matched, truncated = self._call(
				ctx.log_capture.slice_last_seconds, params.lastSeconds, params
			)
			from_command_id = to_command_id = None
			captured_at_level = ctx.log_capture.current_level
		else:
			from_command_id, to_command_id, text, entries, matched, truncated, captured_at_level = (
				self._command_window_slice(ctx, params)
			)

		return protocol.LogSliceResult(
			text=text,
			entries=entries,
			matched=matched,
			truncated=truncated,
			nextPosition=ctx.log_capture.position(),
			fromCommandId=from_command_id,
			toCommandId=to_command_id,
			capturedAtLevel=captured_at_level,
		)

	@staticmethod
	def _check_one_anchor(params: protocol.GetLogParams) -> None:
		by_position = params.sincePosition is not None or params.lastSeconds is not None
		given = sum(1 for v in (params.sincePosition, params.lastSeconds, params.commandId) if v is not None)
		if given > 1:
			raise CommandError(
				"sincePosition, lastSeconds and commandId are mutually exclusive anchors; supply at most one"
			)
		# `windows` belongs to the command anchor and means nothing to the other
		# two, so accepting it there would answer a different question from the
		# one asked -- an agent that sent windows: 3 would be handed a position
		# tail and have no way to tell. Refused for the same reason an unknown
		# field name is: a plausible-looking wrong answer is worse than an error.
		# Only a value the agent cannot have defaulted into counts.
		if by_position and params.windows != 1:
			raise CommandError(
				"windows applies to the commandId anchor only; sincePosition and "
				"lastSeconds already say how far back to read"
			)

	def _command_window_slice(
		self, ctx: SessionContext, params: protocol.GetLogParams
	) -> tuple[int, int, str, int, int, bool, protocol.LogLevel]:
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
		return (
			windows[0][0],
			windows[-1][0],
			text,
			entries,
			matched,
			truncated,
			# The floor in force when the OLDEST window in the range was recorded.
			# If setLogLevel ran mid-range the later windows saw more than this
			# says, which is the safe direction: it never claims to have captured
			# something it did not.
			windows[0][3],
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

	@staticmethod
	def _call(
		method: Any,
		anchor: Any,
		params: protocol.GetLogParams,
	) -> tuple[str, int, int, bool]:
		"""Call *method* (slice_since or slice_last_seconds) with the shared filters."""
		try:
			return method(
				anchor,
				min_level=params.minLevel,
				contains=params.contains,
				exclude=params.exclude,
				fields=params.fields,
				max_entries=max(0, params.maxEntries),
			)
		except ValueError as exc:
			raise CommandError(str(exc)) from None
