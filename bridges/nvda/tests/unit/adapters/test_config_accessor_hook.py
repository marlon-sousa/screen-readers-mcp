# Unit tests for the config_override_hook module.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from typing import Any, ClassVar

from nvdaMcpBridge.adapters.config_override_hook import install, remove


class _FakeSection:
	written: ClassVar[list[tuple[tuple[str, ...], Any]]] = []

	def __init__(self, path: tuple[str, ...]) -> None:
		self.path = path

	def __getitem__(self, key: Any, checkValidity: bool = True) -> str:
		return f"original:{self.path}:{key}"

	def __setitem__(self, key: Any, val: Any) -> None:
		_FakeSection.written.append(((*self.path, key), val))


def setup_function() -> None:
	remove()
	_FakeSection.written.clear()


def teardown_function() -> None:
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
	"""NvdaConfigAccessor keeps adding to the map after install(), so the hook must read it live."""
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

	# A second patch would save the hook itself as the original and make remove() a no-op.
	assert _FakeSection.__getitem__ is first
	assert _FakeSection(("speech",))["synth"] == "x"
	remove()
	assert _FakeSection(("speech",))["synth"] == "original:('speech',):synth"


def test_a_second_install_repoints_the_map() -> None:
	install(_FakeSection, {("a", "b"): "first"})
	install(_FakeSection, {("a", "b"): "second"})
	assert _FakeSection(("a",))["b"] == "second"


def test_remove_is_idempotent() -> None:
	install(_FakeSection, {("x", "x"): "y"})
	remove()
	remove()  # should not raise
	assert _FakeSection(("x",))["x"] == "original:('x',):x"


def test_overrides_are_shared_across_instances() -> None:
	install(_FakeSection, {("speech", "synth"): "shared"})

	assert _FakeSection(("speech",))["synth"] == "shared"
	assert _FakeSection(("speech",))["synth"] == "shared"


# NVDA's settings GUI writes every control back on OK, so a hooked read needs a hooked write.


def test_a_write_to_an_overridden_key_updates_the_map_not_the_profile() -> None:
	overrides = {("speech", "synth"): "espeak"}
	install(_FakeSection, overrides)

	_FakeSection(("speech",))["synth"] = "sapi5"

	assert overrides[("speech", "synth")] == "sapi5"
	assert _FakeSection.written == [], "the write reached NVDA's real config"


def test_a_write_to_any_other_key_falls_through_untouched() -> None:
	install(_FakeSection, {("speech", "synth"): "espeak"})

	_FakeSection(("braille",))["display"] = "noBraille"

	assert _FakeSection.written == [(("braille", "display"), "noBraille")]


def test_the_gui_round_trip_cannot_escape_the_map() -> None:
	overrides = {("speech", "espeak", "sayCapForCapitals"): True}
	install(_FakeSection, overrides)

	section = _FakeSection(("speech", "espeak"))
	shown = section["sayCapForCapitals"]  # what the checkbox displays
	section["sayCapForCapitals"] = shown  # what OK writes back

	assert shown is True, "the dialog should display the override in effect"
	assert overrides[("speech", "espeak", "sayCapForCapitals")] is True
	assert _FakeSection.written == [], "the OK button persisted the override"


def test_writes_are_coerced_by_the_supplied_coercer() -> None:
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
