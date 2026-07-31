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

from typing import Any, ClassVar

from nvdaMcpBridge.adapters.config_override_hook import install, remove


class _FakeSection:
	"""Stand-in for NVDA's AggregatedSection with the .path attribute.

	``written`` records what reached the REAL __setitem__ -- which, for a key
	the session overrode, must be nothing at all.
	"""

	# Deliberately a CLASS attribute: every fake section appends to one list,
	# which is what lets a test assert on all writes at once. ClassVar says so.
	written: ClassVar[list[tuple[tuple[str, ...], Any]]] = []

	def __init__(self, path: tuple[str, ...]) -> None:
		self.path = path

	def __getitem__(self, key: Any, checkValidity: bool = True) -> str:
		return f"original:{self.path}:{key}"

	def __setitem__(self, key: Any, val: Any) -> None:
		_FakeSection.written.append(((*self.path, key), val))


def setup_function() -> None:
	"""No hook installed at the start of each test."""
	remove()
	_FakeSection.written.clear()


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


# -- writes ------------------------------------------------------------------
#
# The leak these close: NVDA's settings GUI reads a value into a control and
# writes every control back on OK. With reads hooked and writes not, that round
# trip lifted the override out of the map and into the real profile, where the
# next save() persisted it.


def test_a_write_to_an_overridden_key_updates_the_map_not_the_profile() -> None:
	overrides = {("speech", "synth"): "espeak"}
	install(_FakeSection, overrides)

	_FakeSection(("speech",))["synth"] = "sapi5"

	assert overrides[("speech", "synth")] == "sapi5"
	assert _FakeSection.written == [], "the write reached NVDA's real config"


def test_a_write_to_any_other_key_falls_through_untouched() -> None:
	"""The session owns the keys it overrode -- not config as a whole."""
	install(_FakeSection, {("speech", "synth"): "espeak"})

	_FakeSection(("braille",))["display"] = "noBraille"

	assert _FakeSection.written == [(("braille", "display"), "noBraille")]


def test_the_gui_round_trip_cannot_escape_the_map() -> None:
	"""Read a value, write it straight back -- exactly what a settings panel does."""
	overrides = {("speech", "espeak", "sayCapForCapitals"): True}
	install(_FakeSection, overrides)

	section = _FakeSection(("speech", "espeak"))
	shown = section["sayCapForCapitals"]  # what the checkbox displays
	section["sayCapForCapitals"] = shown  # what OK writes back

	assert shown is True, "the dialog should display the override in effect"
	assert overrides[("speech", "espeak", "sayCapForCapitals")] is True
	assert _FakeSection.written == [], "the OK button persisted the override"


def test_writes_are_coerced_by_the_supplied_coercer() -> None:
	"""A hooked write is validated exactly as NVDA's own __setitem__ would."""
	overrides: dict[tuple[str, ...], Any] = {("speech", "espeak", "rate"): 50}
	install(_FakeSection, overrides, lambda _path, value: int(value))

	_FakeSection(("speech", "espeak"))["rate"] = "75"

	assert overrides[("speech", "espeak", "rate")] == 75, "stored as the string '75'"


def test_writes_fall_through_again_after_remove() -> None:
	overrides = {("speech", "synth"): "espeak"}
	install(_FakeSection, overrides)
	remove()

	_FakeSection(("speech",))["synth"] = "sapi5"

	assert _FakeSection.written == [(("speech", "synth"), "sapi5")]
	assert overrides[("speech", "synth")] == "espeak", "the map took a post-teardown write"
