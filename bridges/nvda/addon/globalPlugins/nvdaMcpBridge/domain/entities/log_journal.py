# nvdaMcpBridge domain -- LogJournal: the in-memory ring of NVDA log records.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: entity. A bounded ring of structured log records the journal handler feeds
# and ``getLog`` reads. Pure: takes records as tuples, knows nothing about
# ``logging``. Owns the caps, the window marks, the filters and the formatting.
# USED BY: the NvdaLogCapture adapter (feeds records) and the GetLogHandler (reads
# slices).
# BUILT BY: NvdaLogCapture (one per process, cleared each session via reset()).
#
# Records are (level_no, level_name, module, message, timestamp) tuples. The ring
# is bounded at 10 000 records; older ones age out, and a slice that spans aged-out
# records reports ``truncated: true``. A 4 MB secondary cap is tracked approximately
# via the cumulated length of each record's formatted line; whichever cap fires
# first wins.
#
# Window marks are integer positions into the append stream. Because the ring
# overwrites old records, a mark older than the oldest surviving record is
# "expired" -- getLog reports truncated in that case, and the slice contains only
# what survived.

from __future__ import annotations

import logging
from collections import deque

#: Maximum number of records held in the ring.
MAX_RECORDS: int = 10_000

#: Approximate maximum memory in bytes (the sum of formatted-line lengths).
MAX_BYTES: int = 4 * 1024 * 1024

#: The fields a slice renders by default, in order.
DEFAULT_FIELDS: tuple[str, ...] = ("time", "level", "module", "message")

#: Map NVDA log level names to Python logging level numbers for comparison.
_LEVEL_ORDER: dict[str, int] = {
    "debug": logging.DEBUG,
    "io": 5,  # NVDA's custom IO level, below DEBUG (10)
    "debugwarning": 15,  # NVDA's custom DEBUGWARNING, between DEBUG (10) and INFO (20)
    "info": logging.INFO,
    "warning": logging.WARNING,
    "error": logging.ERROR,
}

#: Format string for one record line, like a slice of nvda.log.
_LINE_FORMAT = "{level} - {module} ({time}) - {thread} ({thread_id}):\n{message}"


class LogJournal:
    """Bounded in-memory ring of structured NVDA log records."""

    def __init__(self) -> None:
        # The ring: each entry is (level_no, level_name, module, message, timestamp, thread, thread_id).
        self._records: deque[tuple[int, str, str, str, str, str, int]] = deque()
        # Monotonic append counter; every append increments it, even when the ring
        # drops old records. This is the value mark() returns, and the coordinate
        # space slice() uses.
        self._next_position: int = 0
        # The position of the oldest record still in the ring. When a mark is below
        # this, the window has aged out.
        self._oldest_position: int = 0
        # Approximate memory tracking: sum of formatted-line lengths.
        self._byte_size: int = 0

    # -- feeding ---------------------------------------------------------------

    def append(
        self,
        level_no: int,
        level_name: str,
        module: str,
        message: str,
        timestamp: str,
        thread: str,
        thread_id: int,
    ) -> None:
        """Add one record to the ring, evicting the oldest if at capacity."""
        record = (level_no, level_name, module, message, timestamp, thread, thread_id)
        self._records.append(record)
        self._next_position += 1
        self._byte_size += self._estimate_size(record)
        while len(self._records) > MAX_RECORDS or self._byte_size > MAX_BYTES:
            old = self._records.popleft()
            self._oldest_position += 1
            self._byte_size -= self._estimate_size(old)

    # -- window marks ----------------------------------------------------------

    def mark(self) -> int:
        """Return the current append position (for use as a window bound)."""
        return self._next_position

    # -- slicing ---------------------------------------------------------------

    def slice(
        self,
        start: int,
        end: int,
        *,
        min_level: str | None = None,
        contains: list[str] | None = None,
        exclude: list[str] | None = None,
        fields: list[str] | None = None,
        max_entries: int = 200,
    ) -> tuple[str, int, int, bool]:
        """Return formatted text for records in ``[start, end)`` after applying filters.

        Returns ``(text, entries, matched, truncated)``.
        """
        # How many positions have aged out of the ring?  If the caller's start is
        # before our oldest, the window is partially truncated.
        aged_out = self._oldest_position - start
        truncated = aged_out > 0

        # The surviving slice within the ring.
        first = max(start, self._oldest_position)
        offset = first - self._oldest_position
        surviving = list(self._records)[offset : offset + (end - first)]

        min_level_no = _LEVEL_ORDER.get(min_level) if min_level is not None else None
        contains_lower = [c.lower() for c in contains] if contains else None
        exclude_lower = [e.lower() for e in exclude] if exclude else None
        use_fields = tuple(fields) if fields else DEFAULT_FIELDS

        filtered: list[tuple[int, str, str, str, str, str, int]] = []
        for rec in surviving:
            if min_level_no is not None and rec[0] < min_level_no:
                continue
            if contains_lower is not None:
                msg_lower = rec[3].lower()
                if not any(c in msg_lower for c in contains_lower):
                    continue
            if exclude_lower is not None:
                mod_lower = rec[2].lower()
                msg_lower = rec[3].lower()
                if any(e in mod_lower or e in msg_lower for e in exclude_lower):
                    continue
            filtered.append(rec)

        matched = len(filtered)
        if len(filtered) > max_entries:
            filtered = filtered[:max_entries]
            truncated = True

        lines: list[str] = []
        for rec in filtered:
            lines.append(self._format(rec, use_fields))

        return ("\n".join(lines), len(filtered), matched, truncated)

    # -- helpers ---------------------------------------------------------------

    def reset(self) -> None:
        """Empty the ring (called when a session ends)."""
        self._records.clear()
        self._next_position = 0
        self._oldest_position = 0
        self._byte_size = 0

    def _format(
        self,
        rec: tuple[int, str, str, str, str, str, int],
        fields: tuple[str, ...],
    ) -> str:
        """Render one record with the selected fields."""
        parts: list[str] = []
        for field in fields:
            if field == "time":
                parts.append(rec[4])
            elif field == "level":
                parts.append(rec[1])
            elif field == "module":
                parts.append(rec[2])
            elif field == "message":
                parts.append(rec[3])
            elif field == "thread":
                parts.append(rec[5])
            elif field == "thread_id":
                parts.append(str(rec[6]))
        return " - ".join(parts)

    @staticmethod
    def _estimate_size(
        rec: tuple[int, str, str, str, str, str, int],
    ) -> int:
        """Rough byte estimate: level name + module + message + timestamp + overhead."""
        return len(rec[1]) + len(rec[2]) + len(rec[3]) + len(rec[4]) + len(rec[5]) + 100
