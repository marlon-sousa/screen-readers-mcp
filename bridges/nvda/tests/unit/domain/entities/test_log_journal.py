# Unit tests for domain/entities/log_journal.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import pytest
from nvdaMcpBridge.domain.entities.log_journal import (
    MAX_RECORDS,
    SETTABLE_LEVELS,
    LogJournal,
    wire_level_for,
)


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
    # NVDA's IO is 12, ABOVE DEBUG's 10 -- not 5. Speech is logged at IO, which is
    # why `minLevel: "info"` is the spec's one-step way to drop it.
    _append(j, level_no=12, level_name="IO", message="io msg")
    _append(j, level_no=20, level_name="INFO", message="info msg")
    _append(j, level_no=30, level_name="WARNING", message="warn msg")

    text, entries, matched, _truncated = j.slice(0, j.mark(), min_level="info")
    assert "io msg" not in text
    assert "info msg" in text
    assert "warn msg" in text
    assert entries == 2
    assert matched == 2


def test_io_sits_above_debug_so_debug_keeps_io_records() -> None:
    # The ordering that made the old io=5 harmless-looking and the level REPORTING
    # wrong: asking for debug must keep IO records, because 12 >= 10.
    j = LogJournal()
    _append(j, level_no=10, level_name="DEBUG", message="debug msg")
    _append(j, level_no=12, level_name="IO", message="io msg")

    text, entries, _, _ = j.slice(0, j.mark(), min_level="debug")
    assert "debug msg" in text
    assert "io msg" in text
    assert entries == 2


def test_unknown_min_level_is_rejected_rather_than_ignored() -> None:
    # Silently returning everything for a typo'd level is the worst answer: the
    # agent reads an unfiltered slice as if it were filtered.
    j = LogJournal()
    _append(j)
    with pytest.raises(ValueError, match="unknown log level"):
        j.slice(0, j.mark(), min_level="verbose")


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
    # IO at NVDA's real 12, so this record PASSES min_level="debug" (10) and is
    # dropped by `exclude` on the module. At the old, wrong io=5 the level filter
    # removed it first and the exclude clause was never exercised at all.
    _append(j, level_no=12, level_name="IO", module="speech.speech", message="Speaking hi")
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


# -- the rendered line is nvda.log's own shape ---------------------------------


def test_a_full_field_line_reproduces_nvdas_format() -> None:
    # NVDA writes: "IO - inputCore.InputManager.executeGesture (09:17:40.724) -
    # Thread-5 (13576):\nInput: kb(desktop):v". A slice pasted into an issue has
    # to read like that, which is the reason the default projection exists at all.
    j = LogJournal()
    j.append(12, "IO", "inputCore.InputManager.executeGesture",
             "Input: kb(desktop):v", "09:17:40.724", "Thread-5", 13576)

    text, _, _, _ = j.slice(
        0, 1, fields=["level", "module", "time", "thread", "thread_id", "message"]
    )

    assert text == (
        "IO - inputCore.InputManager.executeGesture (09:17:40.724) - "
        "Thread-5 (13576):\nInput: kb(desktop):v"
    )


def test_the_default_projection_keeps_the_same_shape_minus_the_threads() -> None:
    j = LogJournal()
    j.append(20, "INFO", "core.main", "starting", "09:17:40.724", "MainThread", 1)

    text, _, _, _ = j.slice(0, 1)

    assert text == "INFO - core.main (09:17:40.724):\nstarting"


def test_the_compact_projection_is_level_and_message() -> None:
    # The form the spec calls out as worth reaching for.
    j = LogJournal()
    j.append(20, "INFO", "core.main", "starting", "09:17:40.724", "MainThread", 1)

    text, _, _, _ = j.slice(0, 1, fields=["level", "message"])

    assert text == "INFO:\nstarting"


def test_a_module_only_survey_is_just_the_module_names() -> None:
    # The cheap "what is flooding this window?" call: a few hundred bytes that
    # tell the next call what to exclude, instead of guessing.
    j = LogJournal()
    _append(j, module="speech.speech.speak")
    _append(j, module="IAccessibleHandler.getRole")

    text, _, _, _ = j.slice(0, j.mark(), fields=["module"])

    assert text == "speech.speech.speak\nIAccessibleHandler.getRole"


def test_unknown_field_is_rejected_rather_than_silently_dropped() -> None:
    j = LogJournal()
    _append(j)
    with pytest.raises(ValueError, match="unknown log field"):
        j.slice(0, j.mark(), fields=["level", "mesage"])


# -- level numbers -------------------------------------------------------------


@pytest.mark.parametrize(
    ("level_no", "expected"),
    [
        (0, "debug"),  # NOTSET emits everything: report the most verbose
        (10, "debug"),
        (12, "io"),  # NVDA's IO, between DEBUG and DEBUGWARNING
        (15, "debugwarning"),
        (20, "info"),
        (25, "info"),  # between floors: the coarsest one still admitted
        (30, "warning"),
        (40, "error"),
        (100, "error"),  # NVDA's OFF
    ],
)
def test_wire_level_for_maps_nvdas_numbers(level_no: int, expected: str) -> None:
    assert wire_level_for(level_no) == expected


def test_filter_only_levels_are_not_settable() -> None:
    # warning/error exist in the enum to serve minLevel; setting NVDA's own floor
    # to either would silence warnings in the user's nvda.log.
    assert SETTABLE_LEVELS == {"debug", "io", "debugwarning", "info"}
