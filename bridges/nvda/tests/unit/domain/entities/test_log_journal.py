# Unit tests for domain/entities/log_journal.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from nvdaMcpBridge.domain.entities.log_journal import MAX_RECORDS, LogJournal


def _append(
    journal: LogJournal,
    *,
    level_no: int = 20,
    level_name: str = "INFO",
    module: str = "speech.speech",
    message: str = "Speaking [Elements list]",
    timestamp: str = "2026-07-30 12:00:00.000",
    thread: str = "MainThread",
    thread_id: int = 1234,
) -> None:
    journal.append(level_no, level_name, module, message, timestamp, thread, thread_id)


# -- mark / window bracketing -------------------------------------------------


def test_empty_journal_marks_at_zero() -> None:
    j = LogJournal()
    assert j.mark() == 0


def test_mark_advances_with_appends() -> None:
    j = LogJournal()
    _append(j)
    assert j.mark() == 1
    _append(j)
    assert j.mark() == 2


def test_window_is_empty_when_no_records() -> None:
    j = LogJournal()
    text, entries, matched, truncated = j.slice(0, 0)
    assert text == ""
    assert entries == 0
    assert matched == 0
    assert not truncated


def test_window_contains_only_records_in_range() -> None:
    j = LogJournal()
    _append(j, message="first")
    m1 = j.mark()
    _append(j, message="second")
    _append(j, message="third")
    m2 = j.mark()

    text, entries, matched, truncated = j.slice(m1, m2)
    assert "second" in text
    assert "third" in text
    assert "first" not in text
    assert entries == 2
    assert matched == 2
    assert not truncated


# -- field projection ----------------------------------------------------------


def test_default_fields_are_time_level_module_message() -> None:
    j = LogJournal()
    _append(j, level_name="DEBUG", module="appModules.notepad", message="hello")
    text, _, _, _ = j.slice(0, j.mark())
    assert "DEBUG" in text
    assert "appModules.notepad" in text
    assert "hello" in text


def test_fields_projection_returns_only_requested_fields() -> None:
    j = LogJournal()
    _append(j, level_name="INFO", module="speech.speech", message="Speaking")
    text, _, _, _ = j.slice(0, j.mark(), fields=["level", "message"])
    # Has level and message...
    assert "INFO" in text
    assert "Speaking" in text
    # ...but NOT module or time
    assert "speech.speech" not in text
    assert "2026" not in text


# -- minLevel filter -----------------------------------------------------------


def test_min_level_drops_below_threshold() -> None:
    j = LogJournal()
    _append(j, level_no=5, level_name="IO", message="io msg")
    _append(j, level_no=20, level_name="INFO", message="info msg")
    _append(j, level_no=30, level_name="WARNING", message="warn msg")

    text, entries, matched, _truncated = j.slice(0, j.mark(), min_level="info")
    assert "io msg" not in text
    assert "info msg" in text
    assert "warn msg" in text
    assert entries == 2
    assert matched == 2


# -- contains filter -----------------------------------------------------------


def test_contains_keeps_only_matching_messages() -> None:
    j = LogJournal()
    _append(j, message="COM error 0x80004005")
    _append(j, message="speech started")
    _append(j, message="another COM failure")

    text, entries, matched, _ = j.slice(0, j.mark(), contains=["COM"])
    assert "COM error" in text
    assert "COM failure" in text
    assert "speech started" not in text
    assert entries == 2
    assert matched == 2


def test_contains_is_case_insensitive() -> None:
    j = LogJournal()
    _append(j, message="COM error")
    text, _, _, _ = j.slice(0, j.mark(), contains=["com"])
    assert "COM error" in text


def test_contains_matches_any_substring() -> None:
    j = LogJournal()
    _append(j, message="alpha")
    _append(j, message="beta")
    _append(j, message="gamma")
    text, entries, matched, _ = j.slice(0, j.mark(), contains=["alpha", "gamma"])
    assert "alpha" in text
    assert "gamma" in text
    assert "beta" not in text
    assert entries == 2
    assert matched == 2


# -- exclude filter ------------------------------------------------------------


def test_exclude_drops_matching_module_or_message() -> None:
    j = LogJournal()
    _append(j, module="speech.speech.speak", message="Speaking [Elements list]")
    _append(j, module="IAccessible", message="accName failed")
    _append(j, module="UIAHandler", message="property 30019")

    text, entries, matched, _ = j.slice(0, j.mark(), exclude=["speech"])
    assert "Elements list" not in text
    assert "accName failed" in text
    assert "UIAHandler" in text
    assert entries == 2
    assert matched == 2


def test_exclude_matches_message_too() -> None:
    j = LogJournal()
    _append(j, module="some.module", message="speech output suppressed")
    __text, entries, _, _ = j.slice(0, j.mark(), exclude=["speech"])
    assert entries == 0


def test_exclude_is_case_insensitive() -> None:
    j = LogJournal()
    _append(j, module="SPEECH.speak")
    __text, entries, _, _ = j.slice(0, j.mark(), exclude=["speech"])
    assert entries == 0


# -- filters compose -----------------------------------------------------------


def test_filters_compose() -> None:
    j = LogJournal()
    _append(j, level_no=5, level_name="IO", module="speech.speech", message="Speaking hi")
    _append(j, level_no=10, level_name="DEBUG", module="IAccessible", message="COM error")
    _append(j, level_no=20, level_name="INFO", module="some.module", message="session started")
    _append(j, level_no=10, level_name="DEBUG", module="another", message="debug trace")

    text, entries, matched, _ = j.slice(
        0, j.mark(), min_level="debug", exclude=["speech"], contains=["COM", "trace"]
    )
    assert "COM error" in text
    assert "debug trace" in text
    assert "session started" not in text
    assert "Speaking hi" not in text
    assert entries == 2
    assert matched == 2


# -- maxEntries / truncation ---------------------------------------------------


def test_max_entries_caps_and_reports_truncated() -> None:
    j = LogJournal()
    for i in range(10):
        _append(j, message=f"msg {i}")

    _text, entries, matched, truncated = j.slice(0, j.mark(), max_entries=3)
    assert entries == 3
    assert matched == 10
    assert truncated


def test_no_truncation_when_matched_within_cap() -> None:
    j = LogJournal()
    for i in range(5):
        _append(j, message=f"msg {i}")

    _, entries, matched, truncated = j.slice(0, j.mark(), max_entries=100)
    assert entries == 5
    assert matched == 5
    assert not truncated


# -- ring aging out ------------------------------------------------------------


def test_ring_aging_out_drops_oldest_records() -> None:
    j = LogJournal()
    for i in range(MAX_RECORDS + 5):
        _append(j, message=f"msg {i}")

    # The first 5 records aged out.
    text, _, _, _ = j.slice(0, j.mark())
    assert "msg 0" not in text
    assert "msg 5" in text


def test_expired_window_reports_truncated() -> None:
    j = LogJournal()
    for i in range(MAX_RECORDS + 10):
        _append(j, message=f"msg {i}")

    # Record at position 5 (msg 5) has aged out.
    _, _, _, truncated = j.slice(5, 15)
    assert truncated


# -- reset --------------------------------------------------------------------


def test_reset_empties_the_ring() -> None:
    j = LogJournal()
    _append(j, message="hello")
    assert j.mark() > 0
    j.reset()
    assert j.mark() == 0
    text, entries, _, _ = j.slice(0, 1)
    assert text == ""
    assert entries == 0


# -- thread fields -------------------------------------------------------------


def test_thread_fields_are_recorded() -> None:
    j = LogJournal()
    j.append(20, "INFO", "mod", "msg", "2026-01-01", "MainThread", 42)
    text, _, _, _ = j.slice(0, 1, fields=["thread", "thread_id"])
    assert "MainThread" in text
    assert "42" in text
