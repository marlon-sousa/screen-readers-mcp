# nvdaMcpBridge tests -- unit tests for IniBridgeConfig against FakeConfigFile.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from fakes.config_file import FakeConfigFile
from fakes.log import FakeLog
from nvdaMcpBridge.adapters.ini_bridge_config import IniBridgeConfig
from nvdaMcpBridge.domain.entities.connection_mode import DEFAULT, ConnectionMode
from nvdaMcpBridge.domain.entities.silence_cap import DEFAULT_LIFT_AFTER, DEFAULT_WARN_AFTER

# -- helpers ------------------------------------------------------------------


def _ini(mode: str = "namedPipe", auto_start: str = "false") -> str:
	return f"[nvdaMcpBridge]\nconnectionMode = {mode}\nautoStart = {auto_start}\n"


# -- defaults (no file) -------------------------------------------------------


def test_defaults_when_file_does_not_exist() -> None:
	cfg = IniBridgeConfig(FakeConfigFile(None), FakeLog())
	assert cfg.get_connection_mode() is DEFAULT
	assert cfg.get_auto_start() is False


def test_defaults_when_file_is_empty() -> None:
	cfg = IniBridgeConfig(FakeConfigFile(""), FakeLog())
	assert cfg.get_connection_mode() is DEFAULT
	assert cfg.get_auto_start() is False


# -- read ---------------------------------------------------------------------


def test_reads_connection_mode() -> None:
	cfg = IniBridgeConfig(FakeConfigFile(_ini(mode="loopbackTcp")), FakeLog())
	assert cfg.get_connection_mode() is ConnectionMode.LOOPBACK_TCP


def test_reads_auto_start_true() -> None:
	cfg = IniBridgeConfig(FakeConfigFile(_ini(auto_start="true")), FakeLog())
	assert cfg.get_auto_start() is True


def test_unrecognised_mode_falls_back_to_default() -> None:
	cfg = IniBridgeConfig(FakeConfigFile(_ini(mode="garbage")), FakeLog())
	assert cfg.get_connection_mode() is DEFAULT


# -- write --------------------------------------------------------------------


def test_writes_connection_mode() -> None:
	f = FakeConfigFile(_ini())
	cfg = IniBridgeConfig(f, FakeLog())
	cfg.set_connection_mode(ConnectionMode.LOOPBACK_TCP)
	assert "connectionmode = loopbacktcp" in (f.read() or "").lower()


def test_writes_auto_start() -> None:
	f = FakeConfigFile(_ini())
	cfg = IniBridgeConfig(f, FakeLog())
	cfg.set_auto_start(True)
	assert "autostart = true" in (f.read() or "").lower()


# -- corrupt file -------------------------------------------------------------


def test_corrupt_file_returns_defaults() -> None:
	cfg = IniBridgeConfig(FakeConfigFile("this is not valid ini {{{"), FakeLog())
	assert cfg.get_connection_mode() is DEFAULT
	assert cfg.get_auto_start() is False


# -- round-trip ---------------------------------------------------------------


def test_round_trip_connection_mode() -> None:
	f = FakeConfigFile(None)
	cfg = IniBridgeConfig(f, FakeLog())
	cfg.set_connection_mode(ConnectionMode.LOOPBACK_TCP)
	assert cfg.get_connection_mode() is ConnectionMode.LOOPBACK_TCP


def test_round_trip_auto_start() -> None:
	f = FakeConfigFile(None)
	cfg = IniBridgeConfig(f, FakeLog())
	cfg.set_auto_start(True)
	assert cfg.get_auto_start() is True


# -- the silence cap (spec 0032) ----------------------------------------------
#
# Every read here has to fall to the SAFE side, and "safe" is asymmetric: a cap
# on a machine nobody is sitting at speaks to an empty room, while a missing cap
# on an occupied one leaves a blind person unable to hear their own computer with
# nothing to stop it. So absent, unreadable and nonsensical all mean "assume
# somebody is there, on the shipped thresholds".


def _cap_ini(body: str) -> str:
	return f"[nvdaMcpBridge]\n{body}\n"


def test_a_machine_nobody_has_configured_is_attended() -> None:
	cfg = IniBridgeConfig(FakeConfigFile(None), FakeLog())
	assert cfg.get_unattended() is False
	assert cfg.get_silence_warn_seconds() == DEFAULT_WARN_AFTER
	assert cfg.get_silence_lift_seconds() == DEFAULT_LIFT_AFTER


def test_reads_the_three_keys() -> None:
	cfg = IniBridgeConfig(
		FakeConfigFile(_cap_ini("unattended = true\nsilenceWarnSeconds = 20\nsilenceLiftSeconds = 40")),
		FakeLog(),
	)
	assert cfg.get_unattended() is True
	assert cfg.get_silence_warn_seconds() == 20.0
	assert cfg.get_silence_lift_seconds() == 40.0


def test_an_unreadable_unattended_value_means_attended_and_says_so() -> None:
	log = FakeLog()
	cfg = IniBridgeConfig(FakeConfigFile(_cap_ini("unattended = perhaps")), log)
	assert cfg.get_unattended() is False
	# Worth a line in the log: whoever typed it believes they turned the cap off.
	assert any("unattended" in message for message in log.warnings)


def test_an_unusable_threshold_falls_back_to_the_shipped_one() -> None:
	log = FakeLog()
	cfg = IniBridgeConfig(
		FakeConfigFile(_cap_ini("silenceWarnSeconds = soon\nsilenceLiftSeconds = -3")),
		log,
	)
	assert cfg.get_silence_warn_seconds() == DEFAULT_WARN_AFTER
	assert cfg.get_silence_lift_seconds() == DEFAULT_LIFT_AFTER
	assert len(log.warnings) == 2


def test_a_corrupt_file_leaves_the_cap_in_force() -> None:
	cfg = IniBridgeConfig(FakeConfigFile("this is not valid ini {{{"), FakeLog())
	assert cfg.get_unattended() is False
	assert cfg.get_silence_warn_seconds() == DEFAULT_WARN_AFTER
	assert cfg.get_silence_lift_seconds() == DEFAULT_LIFT_AFTER


def test_round_trip_the_cap_settings() -> None:
	cfg = IniBridgeConfig(FakeConfigFile(None), FakeLog())
	cfg.set_unattended(True)
	cfg.set_silence_warn_seconds(30.0)
	cfg.set_silence_lift_seconds(75.0)
	assert cfg.get_unattended() is True
	assert cfg.get_silence_warn_seconds() == 30.0
	assert cfg.get_silence_lift_seconds() == 75.0


def test_writing_one_setting_leaves_the_others_alone() -> None:
	# Every setter goes through the same read-modify-write, so a checkbox toggled
	# in the dialog must not drop the connection mode beside it.
	f = FakeConfigFile(None)
	cfg = IniBridgeConfig(f, FakeLog())
	cfg.set_connection_mode(ConnectionMode.LOOPBACK_TCP)
	cfg.set_auto_start(True)
	cfg.set_unattended(True)
	assert cfg.get_connection_mode() is ConnectionMode.LOOPBACK_TCP
	assert cfg.get_auto_start() is True
