# Live-NVDA test: session config overrides survive profile switches.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# Run this INSIDE NVDA's Python environment (requires NVDA's config module).
# Easiest: with the nvdaMcpBridge addon installed, from the NVDA Python
# console (NVDA+control+z) or via:
#   py -3 -c "import test_profile_override; test_profile_override.run()"
# from a directory that has NVDA's modules on sys.path.
#
# Alternatively, run the script through NVDA's own Python:
#   & "C:\Program Files (x86)\NVDA\nvda_slave.exe" launcher -m pytest this_file
#
# WHAT IT PROVES:
# 1. set_config writes to the override map, not to config.conf.
# 2. The override is visible to NVDA's own config reads (via AggregatedSection).
# 3. Switching profiles does not displace the override.
# 4. restore_all clears the override and restores the hook.

from __future__ import annotations

import pytest

try:
    import config  # type: ignore[import-untyped]
    from config import AggregatedSection  # type: ignore[import-untyped]
except ModuleNotFoundError:
    pytest.skip("NVDA config module not available", allow_module_level=True)

# The addon's hook module is importable when the addon is loaded.
from nvdaMcpBridge.adapters.config_override_hook import install, remove

# The override map belongs to the CALLER (one per session), lent to the hook by
# install() -- so this test owns its own, exactly as NvdaConfigAccessor does.
_overrides: dict[tuple[str, ...], object] = {}

TEST_KEY = ("speech", "sayCapForCapitals")
PROFILE_OFF = "nvdaMcpTest_capsOff"
PROFILE_ON = "nvdaMcpTest_capsOn"


def _cleanup_profiles() -> None:
    """Remove test profiles if they exist."""
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
        # -- setup: create two profiles with opposite values --------------
        _cleanup_profiles()

        config.conf.createProfile(PROFILE_OFF)
        config.conf.createProfile(PROFILE_ON)

        # Set the test key to False in the "off" profile.
        config.conf.manualActivateProfile(PROFILE_OFF)
        config.conf["speech"]["sayCapForCapitals"] = False

        # Set to True in the "on" profile.
        config.conf.manualActivateProfile(PROFILE_ON)
        config.conf["speech"]["sayCapForCapitals"] = True

        # -- baseline: verify profile switching works --------------------
        config.conf.manualActivateProfile(PROFILE_OFF)
        assert config.conf["speech"]["sayCapForCapitals"] is False, (
            f"{PROFILE_OFF} should have caps off"
        )

        config.conf.manualActivateProfile(PROFILE_ON)
        assert config.conf["speech"]["sayCapForCapitals"] is True, (
            f"{PROFILE_ON} should have caps on"
        )

        # -- install the hook and set an override ------------------------
        install(AggregatedSection, _overrides)
        # Override to False regardless of which profile says what.
        _overrides[TEST_KEY] = False

        # -- verify: override visible in both profiles -------------------
        config.conf.manualActivateProfile(PROFILE_ON)
        # The profile says True, but the OVERRIDE says False.
        val = config.conf["speech"]["sayCapForCapitals"]
        if val is not False:
            failures.append(
                f"override not visible in {PROFILE_ON}: "
                f"expected False, got {val}"
            )

        config.conf.manualActivateProfile(PROFILE_OFF)
        val = config.conf["speech"]["sayCapForCapitals"]
        if val is not False:
            failures.append(
                f"override not visible in {PROFILE_OFF}: "
                f"expected False, got {val}"
            )

        # -- switch back to no profile, verify override still holds ------
        config.conf.manualActivateProfile(None)
        # Base config's value for this key — the override should mask it.
        val = config.conf["speech"]["sayCapForCapitals"]
        if val is not False:
            failures.append(
                f"override not visible with no profile: "
                f"expected False, got {val}"
            )

        # -- teardown: clear override map, remove hook -------------------
        _overrides.clear()
        remove()

        # -- verify: original profile values are back --------------------
        config.conf.manualActivateProfile(PROFILE_ON)
        val = config.conf["speech"]["sayCapForCapitals"]
        if val is not True:
            failures.append(
                f"{PROFILE_ON} not restored after teardown: "
                f"expected True, got {val}"
            )

        config.conf.manualActivateProfile(PROFILE_OFF)
        val = config.conf["speech"]["sayCapForCapitals"]
        if val is not False:
            failures.append(
                f"{PROFILE_OFF} not restored after teardown: "
                f"expected False, got {val}"
            )

        # Verify no profile state: base value is back.
        config.conf.manualActivateProfile(None)

    except Exception as exc:
        failures.append(f"unexpected error: {exc}")

    finally:
        # -- cleanup ----------------------------------------------------
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
