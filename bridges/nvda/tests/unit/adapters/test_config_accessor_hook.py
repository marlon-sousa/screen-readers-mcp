# Unit tests for the config_override_hook module.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# These tests verify the hook mechanism directly, without a live NVDA.
# They provide a stand-in for AggregatedSection, install the hook,
# and assert override behaviour, idempotency, and teardown restoration.
#
# The map is the CALLER's (one per session), lent to the hook by install() --
# so these tests build their own dict exactly as NvdaConfigAccessor does.

from __future__ import annotations

from typing import Any

from nvdaMcpBridge.adapters.config_override_hook import install, remove


class _FakeSection:
    """Stand-in for NVDA's AggregatedSection with the .path attribute."""

    def __init__(self, path: tuple[str, ...]) -> None:
        self.path = path

    def __getitem__(self, key: Any, checkValidity: bool = True) -> str:  # noqa: ARG001
        return f"original:{self.path}:{key}"


def setup_function() -> None:
    """No hook installed at the start of each test."""
    remove()


def teardown_function() -> None:
    """Never leave a patched class behind for the next test."""
    remove()


def test_hook_returns_override_for_matching_path() -> None:
    install(_FakeSection, {("speech", "synth"): "overridden_synth"})

    section = _FakeSection(("speech",))
    assert section["synth"] == "overridden_synth"


def test_hook_falls_through_for_non_matching_path() -> None:
    install(_FakeSection, {("speech", "synth"): "overridden_synth"})

    section = _FakeSection(("braille",))
    assert section["display"] == "original:('braille',):display"


def test_hook_falls_through_when_overrides_is_empty() -> None:
    install(_FakeSection, {})

    section = _FakeSection(("speech",))
    assert section["synth"] == "original:('speech',):synth"


def test_hook_can_override_deep_paths() -> None:
    install(_FakeSection, {("speech", "espeak", "rate"): 50})

    section = _FakeSection(("speech", "espeak"))
    assert section["rate"] == 50


def test_the_map_is_read_live_not_copied() -> None:
    """A key added after install() is still honoured.

    NvdaConfigAccessor installs on the FIRST set() and then keeps adding to the
    same dict, so the hook must read through to the live map rather than having
    snapshotted it.
    """
    overrides: dict[tuple[str, ...], Any] = {}
    install(_FakeSection, overrides)

    assert _FakeSection(("speech",))["synth"] == "original:('speech',):synth"
    overrides[("speech", "synth")] = "added later"
    assert _FakeSection(("speech",))["synth"] == "added later"


def test_remove_hook_restores_original_behaviour() -> None:
    overrides = {("speech", "synth"): "overridden"}
    install(_FakeSection, overrides)
    assert _FakeSection(("speech",))["synth"] == "overridden"

    overrides.clear()
    remove()

    assert _FakeSection(("speech",))["synth"] == "original:('speech',):synth"


def test_install_is_idempotent() -> None:
    install(_FakeSection, {})
    first = _FakeSection.__getitem__
    install(_FakeSection, {("speech", "synth"): "x"})

    # Patched once, so the saved original is the REAL original -- a second patch
    # would have saved the hook itself and made remove() a no-op.
    assert _FakeSection.__getitem__ is first
    assert _FakeSection(("speech",))["synth"] == "x"
    remove()
    assert _FakeSection(("speech",))["synth"] == "original:('speech',):synth"


def test_a_second_install_repoints_the_map() -> None:
    """One session's teardown-less handover must not leak the previous map."""
    install(_FakeSection, {("a", "b"): "first"})
    install(_FakeSection, {("a", "b"): "second"})
    assert _FakeSection(("a",))["b"] == "second"


def test_remove_is_idempotent() -> None:
    install(_FakeSection, {("x", "x"): "y"})
    remove()
    remove()  # should not raise
    assert _FakeSection(("x",))["x"] == "original:('x',):x"


def test_overrides_are_shared_across_instances() -> None:
    """Different AggregatedSection instances see the same overrides."""
    install(_FakeSection, {("speech", "synth"): "shared"})

    assert _FakeSection(("speech",))["synth"] == "shared"
    assert _FakeSection(("speech",))["synth"] == "shared"
