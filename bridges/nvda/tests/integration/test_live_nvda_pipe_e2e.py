# Live-NVDA end-to-end scenario: drive the REAL bridge over a named pipe.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# EXPERIMENTAL, spec 0010's ad-hoc live check -- not a merge gate for entry
# 9.1a. Mirrors test_live_nvda_e2e.py exactly, dialling `DEFAULT_PIPE_NAME`
# with named_pipe_transport.dial() instead of a TCP socket, to prove
# NamedPipeListener against a real NVDA before 9.1b makes the pipe the
# plugin's default for real. Requires plugin.py's uncommitted swap to
# `NamedPipeListener(protocol.DEFAULT_PIPE_NAME)` (see plugin.py) -- with the
# stock TCP-listening addon installed, every test here SKIPS at the dial,
# same as test_live_nvda_e2e.py does with nothing listening.
#
# Run it locally with NVDA up, the pipe-listening build of the addon
# installed, and plugins reloaded (NVDA+control+F3):
#
#     uv run --directory bridges/nvda --with pytest pytest tests/integration/test_live_nvda_pipe_e2e.py -v

from __future__ import annotations

import ast
import time
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import Any

import pytest

#: Every test here drives a REAL NVDA on this machine -- gestures, typed
#: text, config changes. Excluded from the default run; see pyproject.toml.
pytestmark = pytest.mark.live_nvda

from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.adapters import named_pipe_transport
from nvdaMcpBridge.adapters.json_lines_channel import JsonLinesChannel
from nvdaMcpBridge.domain.controllers.commands.registry import NVDA_CAPABILITIES
from nvdaMcpBridge.domain.ports.message_channel import Timeout

#: Same choice as test_live_nvda_e2e.py: speaks in essentially any focus
#: context, so the capture assertion does not depend on a particular window.
SPEAKING_GESTURE = "NVDA+t"

#: The Run dialog is hosted by the shell, so NVDA attributes it to explorer.
RUN_DIALOG_APP_MODULE = "explorer"


@pytest.fixture(scope="module", autouse=True)
def require_live_bridge() -> None:
	try:
		named_pipe_transport.dial(p.DEFAULT_PIPE_NAME, timeout=0.5).close()
	except (OSError, TimeoutError):
		pytest.skip(
			f"no bridge on pipe {p.DEFAULT_PIPE_NAME!r} -- start NVDA with a "
			"pipe-listening build of the nvdaMcpBridge addon installed"
		)


class Agent:
	"""The client end of one bridge session: send a command, read its reply."""

	def __init__(self, channel: JsonLinesChannel) -> None:
		self._channel = channel
		self._id = 0

	def call(self, cmd: str, *, reply_timeout: float = 10.0, **params: Any) -> dict[str, Any]:
		self._id += 1
		self._channel.write(p.Request(id=self._id, cmd=cmd, params=dict(params)))
		deadline = time.monotonic() + reply_timeout
		while time.monotonic() < deadline:
			message = self._channel.read_message()
			if isinstance(message, Timeout):
				continue
			if message.get("error") is not None:
				raise AssertionError(f"{cmd} failed: {message['error']}")
			return message
		raise AssertionError(f"no reply to {cmd} within {reply_timeout}s")

	def result(self, cmd: str, **params: Any) -> dict[str, Any]:
		return self.call(cmd, **params)["result"]

	def close(self) -> None:
		self._channel.close()


def _dial() -> Agent:
	try:
		transport = named_pipe_transport.dial(p.DEFAULT_PIPE_NAME, timeout=1.0)
	except (OSError, TimeoutError):
		pytest.skip(
			f"no bridge on pipe {p.DEFAULT_PIPE_NAME!r} -- start NVDA with a "
			"pipe-listening build of the nvdaMcpBridge addon installed"
		)
	return Agent(JsonLinesChannel(transport))


def _hello(agent: Agent, mode: str) -> dict[str, Any]:
	return agent.result("hello", mode=mode, protocolVersion=p.PROTOCOL_VERSION)


def _expected_bridge_version() -> str:
	"""The add-on version this CHECKOUT would build, read from buildVars.py.

	Parsed rather than imported: buildVars.py pulls in the site_scons tooling,
	so importing it needs SCons installed in whatever interpreter runs pytest.
	The version is a literal keyword argument, and reading it with ast keeps
	this check working in a bare test environment.
	"""
	source = Path(__file__).resolve().parents[2] / "buildVars.py"
	tree = ast.parse(source.read_text(encoding="utf-8"), str(source))
	for node in ast.walk(tree):
		if not isinstance(node, ast.Call):
			continue
		for keyword in node.keywords:
			if keyword.arg == "addon_version" and isinstance(keyword.value, ast.Constant):
				return str(keyword.value.value)
	raise AssertionError(f"no addon_version literal found in {source}")


def _caps_key(agent: Agent) -> list[str]:
	"""The real path of sayCapForCapitals: PER SYNTH, not directly under speech.

	It is declared in [speech][[__many__]] (config/configSpec.py:52-55), and
	NVDA's own voice panel reads it as config.conf["speech"][driver.name][...]
	(gui/settingsDialogs.py:1801). ["speech", "sayCapForCapitals"] is not a real
	key: getConfig on it raises, and an override there is inaudible because
	nothing in NVDA ever reads it.
	"""
	synth = agent.result("getConfig", keyPath=["speech", "synth"])["value"]
	return ["speech", synth, "sayCapForCapitals"]


def test_the_installed_addon_is_the_one_in_this_checkout() -> None:
	"""Guard every other live test in this file against a STALE install.

	These tests import the bridge package from the SOURCE TREE but talk over the
	pipe to whatever add-on build NVDA actually loaded. When the two drift, the
	failures land somewhere else entirely -- a capability list that does not
	match, a command that answers "unknown" -- and read like bridge bugs. Asking
	directly turns a session of confusion into one clear line.

	Caveat worth knowing: this compares VERSIONS, so it catches an install from
	a different release. It cannot catch editing code without bumping
	addon_version; for that the discipline is still rebuild-and-reinstall.
	"""
	agent = _dial()
	try:
		hello = _hello(agent, "silent")
		expected = _expected_bridge_version()
		rebuild = (
			"rebuild and reinstall the add-on (cd bridges/nvda && scons), then restart NVDA"
		)
		# A build predating this field omits it entirely -- which IS the stale
		# case, and the commonest one, so it gets the same clear message rather
		# than a KeyError from the middle of a fixture.
		assert "bridgeVersion" in hello, (
			f"the running bridge does not report bridgeVersion at all, so it predates "
			f"this check; this checkout is {expected!r} -- {rebuild}"
		)
		reported = hello["bridgeVersion"]
		assert reported == expected, (
			f"the running NVDA has bridge {reported!r}, this checkout is {expected!r} -- {rebuild}"
		)
		agent.result("bye")
	finally:
		agent.close()


def test_hello_reports_real_nvda_and_served_capabilities() -> None:
	agent = _dial()
	try:
		hello = _hello(agent, "silent")
		assert hello["reader"]["name"] == "nvda"
		assert hello["reader"]["version"], "reader.version should match About NVDA"
		assert hello["capabilities"] == [c.value for c in NVDA_CAPABILITIES]
		assert hello["mode"] == "silent"
		assert hello["synth"], "hello should report NVDA's real synth"
		agent.result("bye")
	finally:
		agent.close()


def test_silent_session_captures_a_gesture_and_finishes() -> None:
	agent = _dial()
	try:
		_hello(agent, "silent")
		start = agent.result("getNextSpeechIndex")["index"]
		assert agent.result("pressGesture", gestures=[SPEAKING_GESTURE]) == {"ok": True}
		assert agent.result("waitForSpeechToFinish", timeout=3.0)["finished"] is True
		speech = agent.result("getSpeech", sinceIndex=start)
		assert speech["text"].strip(), "the gesture should have been captured as speech"
		assert speech["toIndex"] > speech["fromIndex"]
		agent.result("bye")
	finally:
		agent.close()


def test_two_sequential_sessions_on_one_server() -> None:
	synths: list[str] = []
	for _ in range(2):
		agent = _dial()
		try:
			synths.append(_hello(agent, "silent")["synth"])
			agent.result("bye")
		finally:
			agent.close()
	assert synths[0] == synths[1]
	assert synths[0]  # a real synth name, stable across sessions



@contextmanager
def _run_dialog(agent: Agent) -> Iterator[None]:
	"""Focus the Run dialog for the body, and ALWAYS dismiss it afterwards.

	The Run dialog is the cheapest real focus this suite can borrow: it is
	present on every Windows box, it is a plain edit field that echoes typed
	characters, its app module is a known constant, and Escape puts everything
	back exactly as it was. Nothing is launched and nothing is left running.

	It replaced opening Notepad, which spawned a process, raced the window
	appearing (the poll it needed was ~15s of wall clock in the bad case), and
	left a window on the tester's desktop. None of that bought any coverage.

	The dismissal is in a `finally` because this drives a REAL machine: a failed
	assertion must not walk away leaving a dialog open over someone's work, and
	the text typed here is never committed -- Escape, never Enter, so nothing
	can be executed by accident.
	"""
	agent.result("pressGesture", gestures=["windows+r"])
	try:
		deadline = time.monotonic() + 5.0
		while time.monotonic() < deadline:
			if agent.result("getFocusInfo")["appModule"] == RUN_DIALOG_APP_MODULE:
				break
			time.sleep(0.1)
		else:
			raise AssertionError(
				f"the Run dialog never took focus within 5s (appModule stayed "
				f"{agent.result('getFocusInfo')['appModule']!r})"
			)
		# Let the dialog finish announcing ITSELF before handing over. Focus
		# arrives before the announcement ends, so a body that immediately takes
		# a speech index captures the tail of "Run dialog, Type the name of a
		# program..." and attributes it to whatever it did next.
		agent.result("waitForSpeechToFinish", timeout=5.0)
		yield
	finally:
		agent.result("pressGesture", gestures=["escape"])


# -- introspection e2e (entry 11.1) ------------------------------------------


def test_get_focus_info_reports_real_focus() -> None:
	"""getFocusInfo returns a real role and appModule from the running NVDA."""
	agent = _dial()
	try:
		_hello(agent, "silent")
		result = agent.result("getFocusInfo")
		assert result["role"], "focus role should be non-empty"
		assert isinstance(result["states"], list)

		with _run_dialog(agent):
			focus = agent.result("getFocusInfo")
			assert focus["appModule"] == RUN_DIALOG_APP_MODULE, (
				f"expected the Run dialog to be hosted by "
				f"{RUN_DIALOG_APP_MODULE!r}, got {focus['appModule']!r}"
			)
			# The role is asserted as NON-EMPTY and stable rather than as a
			# specific member: this field's contract is "a stable enum NAME
			# rather than a localized display string" (spec 0015), and which
			# member the Run dialog's field reports is a Windows detail that
			# has changed between releases. Pinning it would test Windows.
			assert focus["role"], "the Run dialog's field should report a role"
			assert focus["role"] == focus["role"].upper(), (
				f"role should be a stable enum NAME, got {focus['role']!r}"
			)

			# Deliberately NOT asserting that typing echoes here. Character echo
			# is a user setting ("speak typed characters"), off on at least one
			# maintainer's machine, and this test is about getFocusInfo -- an
			# assertion that fails on someone's keyboard preferences would be
			# blaming the bridge for the tester's configuration.

		agent.result("bye")
	finally:
		agent.close()


def test_get_state_reports_real_modes() -> None:
	"""getState returns real browseMode, speechMode, sleepMode, inputHelp."""
	agent = _dial()
	try:
		_hello(agent, "silent")
		state = agent.result("getState")
		assert state["browseMode"] in ("browse", "focus", "none")
		assert state["speechMode"] in ("talk", "off", "beeps", "onDemand")
		assert isinstance(state["sleepMode"], bool)
		assert isinstance(state["inputHelp"], bool)
		agent.result("bye")
	finally:
		agent.close()


def test_get_config_reads_real_config_key() -> None:
	"""getConfig reads a known NVDA config key."""
	agent = _dial()
	try:
		_hello(agent, "silent")
		result = agent.result("getConfig", keyPath=["speech", "synth"])
		assert result["value"], "speech.synth should be a non-empty string"
		agent.result("bye")
	finally:
		agent.close()


def test_set_config_roundtrip_and_restore() -> None:
	"""set_config -> get_config sees override; new session sees original."""
	agent = _dial()
	try:
		_hello(agent, "silent")
		original = agent.result(
			"getConfig", keyPath=_caps_key(agent)
		)["value"]

		flipped = not bool(original)
		prior = agent.result(
			"setConfig",
			keyPath=_caps_key(agent),
			value=flipped,
		)["value"]
		assert prior == original, (
			f"setConfig should return prior {original}, got {prior}"
		)

		current = agent.result(
			"getConfig", keyPath=_caps_key(agent)
		)["value"]
		assert current == flipped, (
			f"getConfig should see override {flipped}, got {current}"
		)

		agent.result("bye")
	finally:
		agent.close()

	# New session: override is gone (teardown cleared the map).
	agent2 = _dial()
	try:
		_hello(agent2, "silent")
		restored = agent2.result(
			"getConfig", keyPath=_caps_key(agent2)
		)["value"]
		assert restored == original, (
			f"new session should see original {original}, got {restored}"
		)
		agent2.result("bye")
	finally:
		agent2.close()


def test_set_config_changes_nvda_behaviour() -> None:
	"""set_config changes what NVDA speaks -- the hook reaches NVDA code.

	Asserts that the two spoken results DIFFER, not that either contains a
	particular word. NVDA announces a capital in the tester's own language
	("cap" in English, "maiuscula" in Portuguese), and spec 0015 rejected
	localized strings in assertions for exactly this reason -- an assertion
	that passes or fails depending on the tester's NVDA language is the class
	of flakiness this project exists to remove.
	"""
	agent = _dial()
	try:
		_hello(agent, "silent")
		key = _caps_key(agent)

		def _speak_a_capital() -> str:
			start = agent.result("getNextSpeechIndex")["index"]
			agent.result("typeText", text="A")
			agent.result("waitForSpeechToFinish", timeout=2.0)
			return agent.result("getSpeech", sinceIndex=start)["text"].strip()

		# Type into the Run dialog, not into "whatever happens to have focus".
		# The old form typed a capital A into the tester's foreground window --
		# their editor, their terminal, their email -- which is both a way to
		# corrupt someone's work and a way to get a flaky result, since not
		# every control echoes typed characters.
		with _run_dialog(agent):
			agent.result("setConfig", keyPath=key, value=False)
			without = _speak_a_capital()

			agent.result("setConfig", keyPath=key, value=True)
			with_cap = _speak_a_capital()

		# sayCapForCapitals is only audible through TYPED-CHARACTER ECHO, which
		# is itself a user setting. With echo off there is simply nothing to
		# observe, and failing would blame the bridge for the tester's NVDA
		# configuration -- so say what is actually wrong and skip.
		if not without and not with_cap:
			pytest.skip(
				"NVDA announced nothing for a typed capital in either state, so "
				"'speak typed characters' is off -- sayCapForCapitals has no "
				"audible effect to measure. Enable it in Keyboard settings."
			)

		assert with_cap != without, (
			"turning sayCapForCapitals on did not change what NVDA spoke for a "
			f"capital A (both were {without!r}) -- the override never reached NVDA"
		)
		assert len(with_cap) > len(without), (
			f"expected the announcement to GAIN a capital marker, got {without!r} -> {with_cap!r}"
		)

		agent.result("bye")
	finally:
		agent.close()
