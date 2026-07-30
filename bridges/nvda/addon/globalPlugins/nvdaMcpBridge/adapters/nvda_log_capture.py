# nvdaMcpBridge adapters -- NvdaLogCapture: journals NVDA's log for one session.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the LogCapture domain port with NVDA's own logging
#       machinery. On pyright's ignore list (imports NVDA via ``logHandler``);
#       validated by the live-NVDA checklist (spec 0020), not the type checker.
# BUILT BY: plugin.py (once, like NvdaSessionSignals/NvdaAnnouncer) and injected
#           via wiring.build_session.
# USED BY: the hello handler (start, with the requested level), SetLogLevelHandler
#          (set_level), GetLogHandler (position/slice), and the Session's teardown
#          (stop, unconditionally).
#
# A reused singleton, not built fresh per connection: the bridge serves one
# session at a time (AGENTS.md), so start()/stop() simply reset this instance's
# per-session state each time.
#
# Supersedes 0009's FileHandler: the journal replaces the per-session capture file.
# The level raise is global (on ``log.root``), so NVDA's own ``nvda.log`` already
# holds identical records; the session transcript's timestamps bracket the window
# in it. A ``logging.Handler`` subclass feeds records into the LogJournal entity
# BEFORE formatting, so filtering is exact and projection is free.

from __future__ import annotations

import logging
import os
from datetime import datetime
from typing import TYPE_CHECKING

from logHandler import log

from ..domain.entities.log_journal import LogJournal
from ..domain.ports.log_capture import LogCapture

if TYPE_CHECKING:
    from .. import protocol


class _JournalHandler(logging.Handler):
    """A logging handler that writes structured records into a LogJournal."""

    def __init__(self, journal: LogJournal) -> None:
        super().__init__()
        self.journal = journal

    def emit(self, record: logging.LogRecord) -> None:
        timestamp = datetime.fromtimestamp(
            record.created, datetime.timezone.utc
        ).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        self.journal.append(
            record.levelno,
            record.levelname,
            record.name,
            record.getMessage(),
            timestamp,
            record.threadName,
            record.thread,
        )


class NvdaLogCapture(LogCapture):
    """Journals NVDA's log into an in-memory LogJournal, replacing 0009's file."""

    def __init__(self) -> None:
        self._journal = LogJournal()
        self._handler: _JournalHandler | None = None
        self._previous_level: int | None = None
        self._previous_level_name: protocol.LogLevel | None = None
        self._current_level: protocol.LogLevel | None = None

    # -- port implementation ---------------------------------------------------

    @property
    def path(self) -> str:
        return ""  # Superseded by 0020; no capture file.

    @property
    def current_level(self) -> protocol.LogLevel:
        assert self._current_level is not None, "current_level read before start()"
        return self._current_level

    def start(self, level: protocol.LogLevel | None) -> None:
        from .. import protocol

        self._journal.reset()
        handler = _JournalHandler(self._journal)
        self._previous_level = log.root.level
        # Map the requested wire level to NVDA's logger level number, or leave
        # the root logger unchanged if no level was requested.
        if level is not None:
            nvda_level = getattr(log, level.name)
            log.root.setLevel(nvda_level)
        log.root.addHandler(handler)
        self._handler = handler
        # Record the level now in force for capturedAtLevel reporting.
        effective = level or self._nvda_level_to_wire(log.root.level)
        self._previous_level_name = self._current_level
        self._current_level = effective

    def stop(self) -> None:
        if self._handler is None:
            return
        log.root.removeHandler(self._handler)
        self._handler = None
        if self._previous_level is not None:
            log.root.setLevel(self._previous_level)
            self._previous_level = None
        if self._previous_level_name is not None:
            self._current_level = self._previous_level_name
            self._previous_level_name = None
        self._journal.reset()

    def position(self) -> int:
        return self._journal.mark()

    def slice(
        self, start: int, end: int, *,
        min_level: protocol.LogLevel | None = None,
        contains: list[str] | None = None,
        exclude: list[str] | None = None,
        fields: list[str] | None = None,
        max_entries: int = 200,
    ) -> protocol.LogSliceResult:
        from .. import protocol

        text, entries, matched, truncated = self._journal.slice(
            start, end,
            min_level=min_level.value if min_level else None,
            contains=contains,
            exclude=exclude,
            fields=fields,
            max_entries=max_entries,
        )
        return protocol.LogSliceResult(
            text=text, entries=entries, matched=matched, truncated=truncated,
            fromCommandId=0, toCommandId=0,
            capturedAtLevel=self._current_level or protocol.LogLevel.INFO,
        )

    def set_level(self, level: protocol.LogLevel) -> None:
        from .. import protocol

        self._previous_level_name = self._current_level
        nvda_level = getattr(log, level.name)
        log.root.setLevel(nvda_level)
        self._current_level = level

    # -- helpers ---------------------------------------------------------------

    @staticmethod
    def _nvda_level_to_wire(level_no: int) -> protocol.LogLevel:
        """Map an NVDA logger level number to the wire enum."""
        from .. import protocol

        if level_no <= 5:
            return protocol.LogLevel.IO
        elif level_no <= 10:
            return protocol.LogLevel.DEBUG
        elif level_no <= 15:
            return protocol.LogLevel.DEBUGWARNING
        elif level_no <= 20:
            return protocol.LogLevel.INFO
        elif level_no <= 30:
            return protocol.LogLevel.WARNING
        else:
            return protocol.LogLevel.ERROR
