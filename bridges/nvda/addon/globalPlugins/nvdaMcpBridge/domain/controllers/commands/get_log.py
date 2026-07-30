# nvdaMcpBridge domain -- GetLogHandler: the getLog command.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for ``getLog`` -- returns a filtered, formatted slice of
# NVDA's log for one or more command windows. Anchored by request id; defaults to
# the most recently marked command. Does not mark itself (marks_log = False).
# USES: the LogCapture port (the journal behind it), the Session's command-window
# list through the SessionContext.

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
            anchor_id = params.commandId
            window_index = ctx.command_window_index(anchor_id)
            if window_index is None:
                raise CommandError(
                    f"command id {anchor_id} not found among the last "
                    f"{len(ctx.command_windows)} marked commands"
                )
        else:
            if not ctx.command_windows:
                raise CommandError("no commands have been marked yet")
            window_index = -1  # most recent

        # Collect `windows` windows, counting back from the anchor.
        windows_count = max(1, params.windows)
        actual_windows = ctx.command_windows_for(window_index, windows_count)
        if not actual_windows:
            raise CommandError("no command windows within range")

        from_id = actual_windows[0][0]
        to_id = actual_windows[-1][0]

        # All windows in the slice were recorded at the same level (the floor then
        # in force). If a window straddles a level change the floor is the one at
        # the START of the range, which is what `capturedAtLevel` reports for the
        # first window. For multi-window slices, report the floor of the first one.
        captured_at_level = actual_windows[0][3]
        start_pos = actual_windows[0][1]
        end_pos = actual_windows[-1][2]

        result = ctx.log_capture.slice(
            start_pos,
            end_pos,
            min_level=params.minLevel,
            contains=params.contains,
            exclude=params.exclude,
            fields=params.fields,
            max_entries=params.maxEntries,
        )

        result.fromCommandId = from_id
        result.toCommandId = to_id
        result.capturedAtLevel = captured_at_level

        return result
