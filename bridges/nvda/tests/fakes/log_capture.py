# nvdaMcpBridge tests -- FakeLogCapture, standing in for the LogCapture port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# FAKES: domain/ports/log_capture.py
#
# Holds an in-memory LogJournal so the filters and window bracketing are exercised
# through the real entity rather than re-implemented here. The level change and
# restore machinery mirrors the real adapter's shape: start remembers the previous
# level, set_level changes it, stop restores it.

from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Any

from nvdaMcpBridge.domain.entities.log_journal import LogJournal
from nvdaMcpBridge.domain.ports.log_capture import LogCapture

if TYPE_CHECKING:
    from nvdaMcpBridge import protocol as p


@dataclass
class _SliceCall:
    """Record of a slice() call, for test assertions."""
    start: int
    end: int
    min_level: p.LogLevel | None = None
    contains: list[str] | None = None
    exclude: list[str] | None = None
    fields: list[str] | None = None
    max_entries: int = 200


class FakeLogCapture(LogCapture):
    """An in-memory :class:`LogCapture` backed by a real LogJournal."""

    def __init__(self, *, fail_on: set[str] | None = None) -> None:
        self._fail_on = fail_on or set()
        self._journal = LogJournal()
        self._level: p.LogLevel | None = None
        self._previous_level: p.LogLevel | None = None
        # Public for test assertions.
        self.events: list[tuple[Any, ...]] = []
        self.slice_calls: list[_SliceCall] = []

    # -- port implementation ---------------------------------------------------

    @property
    def path(self) -> str:
        return ""  # Superseded by 0020; kept for the port's abstract contract.

    @property
    def current_level(self) -> p.LogLevel:
        from nvdaMcpBridge import protocol
        return self._level if self._level is not None else protocol.LogLevel.INFO

    def start(self, level: p.LogLevel | None) -> None:
        from nvdaMcpBridge import protocol

        self._record("start", level)
        if level is not None:
            self._previous_level = self._level
            self._level = level
        else:
            # Default to INFO when no level is requested (spec 0020: the journal
            # always has a floor, even when the caller didn't request one).
            self._level = protocol.LogLevel.INFO

    def stop(self) -> None:
        self._record("stop")
        if self._previous_level is not None:
            self._level = self._previous_level
            self._previous_level = None
        self._journal.reset()

    def position(self) -> int:
        return self._journal.mark()

    def slice(
        self, start: int, end: int, *,
        min_level: p.LogLevel | None = None,
        contains: list[str] | None = None,
        exclude: list[str] | None = None,
        fields: list[str] | None = None,
        max_entries: int = 200,
    ) -> p.LogSliceResult:
        from nvdaMcpBridge import protocol

        self.slice_calls.append(_SliceCall(
            start=start, end=end,
            min_level=min_level, contains=contains,
            exclude=exclude, fields=fields, max_entries=max_entries,
        ))
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
            capturedAtLevel=self._level or protocol.LogLevel.INFO,
        )

    def set_level(self, level: p.LogLevel) -> None:
        self._record("set_level", level)
        self._previous_level = self._level
        self._level = level

    # -- helpers ---------------------------------------------------------------

    def _record(self, name: str, *args: Any) -> None:
        self.events.append((name, *args))
        if name in self._fail_on:
            raise RuntimeError(f"log capture failing on {name}")

    def feed(self, message: str, *, level_no: int = 20, level_name: str = "INFO",
             module: str = "test.module", timestamp: str = "2026-01-01 00:00:00.000",
             thread: str = "MainThread", thread_id: int = 1) -> None:
        """Add a record to the journal (for tests that need content to slice)."""
        self._journal.append(level_no, level_name, module, message, timestamp, thread, thread_id)

    def feed_record(self, level_no: int, level_name: str, module: str, message: str,
                    timestamp: str, thread: str = "MainThread", thread_id: int = 1) -> None:
        """Add a fully specified record to the journal."""
        self._journal.append(level_no, level_name, module, message, timestamp, thread, thread_id)
