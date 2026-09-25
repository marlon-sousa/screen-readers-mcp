# nvdaMcpBridge domain -- GetLogHandler: the getLog command.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `getLog`: a filtered slice of NVDA's log, anchored by sincePosition,
#       lastSeconds or commandId, the default.
# A multi-window request is one span, gaps included: in NVDA 2026.1 the speech a gesture causes is logged
# about a millisecond after the command's window closes.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandError, CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class GetLogHandler(CommandHandler):
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
		# windows with a position anchor is refused, not ignored: a plausible wrong answer is worse.
		if by_position and params.windows != 1:
			raise CommandError(
				"windows applies to the commandId anchor only; sincePosition and "
				"lastSeconds already say how far back to read"
			)

	def _command_window_slice(
		self, ctx: SessionContext, params: protocol.GetLogParams
	) -> tuple[int, int, str, int, int, bool, protocol.LogLevel]:
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
			window_index = -1

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
			# The level when the oldest window was recorded, so it never claims more than was captured.
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
			# An unknown field name or level is the agent's error, not a fault.
			raise CommandError(str(exc)) from None

	@staticmethod
	def _call(
		method: Any,
		anchor: Any,
		params: protocol.GetLogParams,
	) -> tuple[str, int, int, bool]:
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
