# Live-NVDA test: session config overrides survive profile switches.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# Runs inside NVDA's own Python, for example from the NVDA Python console; skips without NVDA's config module.

from __future__ import annotations

import pytest

#: Drives a real NVDA on this machine; excluded from the default run.
pytestmark = pytest.mark.live_nvda

try:
	import config  # type: ignore[import-untyped]
	from config import AggregatedSection  # type: ignore[import-untyped]
except ModuleNotFoundError:
	pytest.skip("NVDA config module not available", allow_module_level=True)

from nvdaMcpBridge.adapters.config_override_hook import install, remove

# The caller owns the override map, as NvdaConfigAccessor does.
_overrides: dict[tuple[str, ...], object] = {}


#: sayCapForCapitals is per synth; see _caps_key in test_live_nvda_pipe_e2e.py.
def _test_key() -> tuple[str, ...]:
	return ("speech", config.conf["speech"]["synth"], "sayCapForCapitals")


def _conf_value() -> object:
	section, leaf = _test_key()[:-1], _test_key()[-1]
	node: object = config.conf
	for part in section:
		node = node[part]  # type: ignore[index]
	return node[leaf]  # type: ignore[index]


def _set_conf_value(value: object) -> None:
	section, leaf = _test_key()[:-1], _test_key()[-1]
	node: object = config.conf
	for part in section:
		node = node[part]  # type: ignore[index]
	node[leaf] = value  # type: ignore[index]


PROFILE_OFF = "nvdaMcpTest_capsOff"
PROFILE_ON = "nvdaMcpTest_capsOn"


def _cleanup_profiles() -> None:
	for name in list(config.conf.listProfiles()):
		if name.startswith("nvdaMcpTest_"):
			try:
				config.conf.deleteProfile(name)
			except Exception:
				pass


def run() -> int:
	"""Run the profile-override test. Returns 0 on success, 1 on failure."""
	failures: list[str] = []

	try:
		_cleanup_profiles()

		config.conf.createProfile(PROFILE_OFF)
		config.conf.createProfile(PROFILE_ON)

		config.conf.manualActivateProfile(PROFILE_OFF)
		_set_conf_value(False)

		config.conf.manualActivateProfile(PROFILE_ON)
		_set_conf_value(True)

		config.conf.manualActivateProfile(PROFILE_OFF)
		assert _conf_value() is False, f"{PROFILE_OFF} should have caps off"

		config.conf.manualActivateProfile(PROFILE_ON)
		assert _conf_value() is True, f"{PROFILE_ON} should have caps on"

		install(AggregatedSection, _overrides)
		_overrides[_test_key()] = False

		config.conf.manualActivateProfile(PROFILE_ON)
		val = _conf_value()
		if val is not False:
			failures.append(f"override not visible in {PROFILE_ON}: expected False, got {val}")

		config.conf.manualActivateProfile(PROFILE_OFF)
		val = _conf_value()
		if val is not False:
			failures.append(f"override not visible in {PROFILE_OFF}: expected False, got {val}")

		config.conf.manualActivateProfile(None)
		val = _conf_value()
		if val is not False:
			failures.append(f"override not visible with no profile: expected False, got {val}")

		# NVDA's settings panel writes every value back on OK; that must stay in the map and dirty no profile.
		config.conf.manualActivateProfile(PROFILE_ON)
		dirty_before = set(getattr(config.conf, "_dirtyProfiles", ()))
		_set_conf_value(_conf_value())  # read it, write it straight back

		if _overrides.get(_test_key()) is not False:
			failures.append(
				"a write to an overridden key did not land in the map: "
				f"map now holds {_overrides.get(_test_key())!r}"
			)
		if set(getattr(config.conf, "_dirtyProfiles", ())) != dirty_before:
			failures.append(
				"a write to an overridden key marked a profile dirty; "
				"the next save() would persist the override to disk"
			)

		untouched = ("speech", "symbolLevel")
		try:
			before = config.conf["speech"]["symbolLevel"]
			config.conf["speech"]["symbolLevel"] = before
		except Exception as exc:
			failures.append(f"a non-overridden write did not pass through: {exc}")
		del untouched

		_overrides.clear()
		remove()

		config.conf.manualActivateProfile(PROFILE_ON)
		val = _conf_value()
		if val is not True:
			failures.append(f"{PROFILE_ON} not restored after teardown: expected True, got {val}")

		config.conf.manualActivateProfile(PROFILE_OFF)
		val = _conf_value()
		if val is not False:
			failures.append(f"{PROFILE_OFF} not restored after teardown: expected False, got {val}")

		config.conf.manualActivateProfile(None)

	except Exception as exc:
		failures.append(f"unexpected error: {exc}")

	finally:
		try:
			_overrides.clear()
			remove()
		except Exception:
			pass
		try:
			config.conf.manualActivateProfile(None)
		except Exception:
			pass
		_cleanup_profiles()

	if failures:
		for f in failures:
			print(f"FAIL: {f}")
		return 1
	print("OK: profile override test passed")
	return 0


if __name__ == "__main__":
	raise SystemExit(run())
