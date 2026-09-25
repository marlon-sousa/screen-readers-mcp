# Live-NVDA end-to-end scenario: drive the real bridge over a named pipe.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# Dials the real NVDA's bridge on DEFAULT_PIPE_NAME; every test skips when nothing listens.

from __future__ import annotations

import ast
import time
from pathlib import Path
from typing import Any

import pytest
from support.platforms import skip_module_unless_windows

#: Drives a real NVDA on this machine; excluded from the default run.
pytestmark = pytest.mark.live_nvda

# The marker alone is not enough; see tests/support/platforms.py.
skip_module_unless_windows("dials a real named pipe, which is a Win32 facility")

from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.adapters import named_pipe_transport
from nvdaMcpBridge.adapters.json_lines_channel import JsonLinesChannel
from nvdaMcpBridge.domain.controllers.commands.registry import NVDA_CAPABILITIES
from nvdaMcpBridge.domain.ports.message_channel import Timeout

#: Speaks in essentially any focus context.
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
	def __init__(self, channel: JsonLinesChannel) -> None:
		self._channel = channel
		self._id = 0

	def raw(self, cmd: str, *, reply_timeout: float = 10.0, **params: Any) -> dict[str, Any]:
		"""The reply as it came, error included, for tests whose subject is a refusal."""
		self._id += 1
		self._channel.write(p.Request(id=self._id, cmd=cmd, params=dict(params)))
		deadline = time.monotonic() + reply_timeout
		while time.monotonic() < deadline:
			message = self._channel.read_message()
			if isinstance(message, Timeout):
				continue
			return message
		raise AssertionError(f"no reply to {cmd} within {reply_timeout}s")

	def call(self, cmd: str, *, reply_timeout: float = 10.0, **params: Any) -> dict[str, Any]:
		reply = self.raw(cmd, reply_timeout=reply_timeout, **params)
		if reply.get("error") is not None:
			raise AssertionError(f"{cmd} failed: {reply['error']}")
		return reply

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
	"""Parsed, not imported: importing buildVars.py needs SCons."""
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
	"""In NVDA 2026.1 sayCapForCapitals lives per synth, under ["speech", <synth>]."""
	synth = agent.result("getConfig", keyPath=["speech", "synth"])["value"]
	return ["speech", synth, "sayCapForCapitals"]


def _settled_index(agent: Agent, *, settle: float = 0.4, timeout: float = 4.0) -> int:
	"""Waits for the index to hold still: waitForSpeechToFinish speaks only for the last utterance."""
	last = agent.result("getNextSpeechIndex")["index"]
	quiet_since = time.monotonic()
	deadline = time.monotonic() + timeout
	while time.monotonic() < deadline:
		time.sleep(0.1)
		now = agent.result("getNextSpeechIndex")["index"]
		if now != last:
			last, quiet_since = now, time.monotonic()
		elif time.monotonic() - quiet_since >= settle:
			return last
	return last


def _speech_after(agent: Agent, start: int, *, timeout: float = 4.0) -> str:
	"""Waits for the index to move first, so an announcement not yet begun is not read as silence."""
	deadline = time.monotonic() + timeout
	while time.monotonic() < deadline:
		if agent.result("getNextSpeechIndex")["index"] > start:
			break
		time.sleep(0.1)
	_settled_index(agent)
	speech = agent.result("getSpeech", sinceIndex=start)
	return "\n".join(entry["text"] for entry in speech["entries"]).strip()


def test_the_installed_addon_is_the_one_in_this_checkout() -> None:
	"""Compares versions only; an edit without an addon_version bump still needs a rebuild and reinstall."""
	agent = _dial()
	try:
		hello = _hello(agent, "silent")
		expected = _expected_bridge_version()
		rebuild = "rebuild and reinstall the add-on (cd bridges/nvda && scons), then restart NVDA"
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
		pressed = agent.result("pressGesture", gestures=[SPEAKING_GESTURE])
		assert [press["gesture"] for press in pressed["pressed"]] == [SPEAKING_GESTURE]
		assert pressed["speechTo"] >= pressed["speechFrom"] >= start
		assert agent.result("waitForSpeechToFinish", timeout=3.0)["finished"] is True
		speech = agent.result("getSpeech", sinceIndex=start)
		spoken = "\n".join(entry["text"] for entry in speech["entries"])
		assert spoken.strip(), "the gesture should have been captured as speech"
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


class _RunDialog:
	"""Focuses the Run dialog for the block and always dismisses it with Escape, never Enter."""

	def __init__(self, agent: Agent) -> None:
		self._agent = agent

	def __enter__(self) -> None:
		self._agent.result("pressGesture", gestures=["windows+r"])
		deadline = time.monotonic() + 5.0
		while time.monotonic() < deadline:
			if self._agent.result("getFocusInfo")["appModule"] == RUN_DIALOG_APP_MODULE:
				break
			time.sleep(0.1)
		else:
			self._agent.result("pressGesture", gestures=["escape"])
			raise AssertionError(
				f"the Run dialog never took focus within 5s (appModule stayed "
				f"{self._agent.result('getFocusInfo')['appModule']!r})"
			)
		# Focus arrives before the dialog's own announcement ends; wait, or the body captures its tail.
		self._agent.result("waitForSpeechToFinish", timeout=5.0)

	def __exit__(self, *exc_info: object) -> None:
		self._agent.result("pressGesture", gestures=["escape"])


def test_get_focus_info_reports_real_focus() -> None:
	agent = _dial()
	try:
		_hello(agent, "silent")
		result = agent.result("getFocusInfo")
		assert result["role"], "focus role should be non-empty"
		assert isinstance(result["states"], list)

		with _RunDialog(agent):
			focus = agent.result("getFocusInfo")
			assert focus["appModule"] == RUN_DIALOG_APP_MODULE, (
				f"expected the Run dialog to be hosted by "
				f"{RUN_DIALOG_APP_MODULE!r}, got {focus['appModule']!r}"
			)
			# A stable enum name, not a member: which one the Run dialog reports varies by Windows release.
			assert focus["role"], "the Run dialog's field should report a role"
			assert focus["role"] == focus["role"].upper(), (
				f"role should be a stable enum NAME, got {focus['role']!r}"
			)

		agent.result("bye")
	finally:
		agent.close()


def test_get_state_reports_real_modes() -> None:
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
	agent = _dial()
	try:
		_hello(agent, "silent")
		result = agent.result("getConfig", keyPath=["speech", "synth"])
		assert result["value"], "speech.synth should be a non-empty string"
		agent.result("bye")
	finally:
		agent.close()


def test_set_config_roundtrip_and_restore() -> None:
	agent = _dial()
	try:
		_hello(agent, "silent")
		original = agent.result("getConfig", keyPath=_caps_key(agent))["value"]

		flipped = not bool(original)
		prior = agent.result(
			"setConfig",
			keyPath=_caps_key(agent),
			value=flipped,
		)["value"]
		assert prior == original, f"setConfig should return prior {original}, got {prior}"

		current = agent.result("getConfig", keyPath=_caps_key(agent))["value"]
		assert current == flipped, f"getConfig should see override {flipped}, got {current}"

		agent.result("bye")
	finally:
		agent.close()

	agent2 = _dial()
	try:
		_hello(agent2, "silent")
		restored = agent2.result("getConfig", keyPath=_caps_key(agent2))["value"]
		assert restored == original, f"new session should see original {original}, got {restored}"
		agent2.result("bye")
	finally:
		agent2.close()


def test_set_config_changes_nvda_behaviour() -> None:
	"""Asserts the two results differ, never a word: NVDA speaks capitals in the tester's language."""
	agent = _dial()
	try:
		_hello(agent, "silent")
		key = _caps_key(agent)

		def _speak_a_capital() -> str:
			"""NVDA 2026.1 does not echo injected KEYEVENTF_UNICODE text; arrow onto it instead."""
			agent.result("pressGesture", gestures=["control+a"])
			agent.result("typeText", text="A")
			start = _settled_index(agent)
			agent.result("pressGesture", gestures=["leftArrow"])
			return _speech_after(agent, start)

		with _RunDialog(agent):
			agent.result("setConfig", keyPath=key, value=False)
			without = _speak_a_capital()

			agent.result("setConfig", keyPath=key, value=True)
			with_cap = _speak_a_capital()

		assert without, "arrowing onto a character announced nothing at all"
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


# askUser returns immediately, so the same session can send the acknowledgement gesture itself.


def test_ask_user_round_trip_with_the_real_acknowledgement_gesture() -> None:
	agent = _dial()
	try:
		_hello(agent, "silent")

		ticket = agent.result("askUser", prompt="This is an automated test. No action needed.")["ticket"]
		assert ticket, "askUser returned no ticket"

		missed = agent.result("waitForUserReply", ticket=ticket, timeout=0.5)
		assert missed["answered"] is False, "a prompt nobody answered reported answered=true"

		agent.result("pressGesture", gestures=["NVDA+control+shift+a"])

		answered = agent.result("waitForUserReply", ticket=ticket, timeout=5.0)
		assert answered["answered"] is True, (
			"the acknowledgement gesture did not answer the prompt -- the ack script "
			"could not reach the session's outstanding prompt"
		)

		with pytest.raises(AssertionError, match="no outstanding prompt"):
			agent.call("waitForUserReply", ticket=ticket, timeout=0.5)

		agent.result("bye")
	finally:
		agent.close()


def test_nothing_the_tester_hears_during_the_window_is_captured() -> None:
	agent = _dial()
	try:
		_hello(agent, "silent")

		before = agent.result("getNextSpeechIndex")["index"]
		ticket = agent.result("askUser", prompt="Automated test. Ignore this.")["ticket"]

		agent.result("pressGesture", gestures=[SPEAKING_GESTURE])
		time.sleep(0.5)

		during = agent.result("getNextSpeechIndex")["index"]
		assert during == before, (
			f"speech index moved {before} -> {during} while the window was open: "
			"the tester's own speech is being captured as if it were reader output"
		)

		agent.result("pressGesture", gestures=["NVDA+control+shift+a"])
		assert agent.result("waitForUserReply", ticket=ticket, timeout=5.0)["answered"] is True

		agent.result("pressGesture", gestures=[SPEAKING_GESTURE])
		time.sleep(0.5)
		after = agent.result("getNextSpeechIndex")["index"]
		assert after > during, (
			f"speech index stuck at {during} after the window closed -- suppression "
			"did not resume, so nothing is being captured any more"
		)

		agent.result("bye")
	finally:
		agent.close()


def test_a_session_that_dies_with_a_window_open_recovers() -> None:
	# A fresh session capturing speech proves the dropped one released cleanly.
	agent = _dial()
	try:
		_hello(agent, "silent")
		agent.result("askUser", prompt="Automated test. This session will drop.")
	finally:
		agent.close()  # no bye, no answer -- the agent just vanishes

	time.sleep(1.0)

	recovered = _dial()
	try:
		_hello(recovered, "silent")
		before = recovered.result("getNextSpeechIndex")["index"]
		recovered.result("pressGesture", gestures=[SPEAKING_GESTURE])
		time.sleep(0.5)
		after = recovered.result("getNextSpeechIndex")["index"]
		assert after > before, (
			"a fresh session captured nothing, so the abandoned window left the "
			"bridge in a state it could not recover from"
		)
		recovered.result("bye")
	finally:
		recovered.close()


def test_the_acknowledgement_is_confirmed_out_loud() -> None:
	# Live mode only: in silent mode the open window sends the confirmation to the synth, never the buffer.
	agent = _dial()
	try:
		_hello(agent, "live")
		ticket = agent.result("askUser", prompt="Automated test. Ignore this.")["ticket"]

		start = _settled_index(agent)
		agent.result("pressGesture", gestures=["NVDA+control+shift+a"])
		spoken = _speech_after(agent, start)

		assert spoken, (
			"the acknowledgement gesture said NOTHING; silence is indistinguishable "
			"from a keypress that missed the dialog"
		)
		# Our own string, which has no translation yet.
		assert "acknowledg" in spoken.casefold(), (
			f"the gesture spoke {spoken!r}, which is not the confirmation"
		)
		assert agent.result("waitForUserReply", ticket=ticket, timeout=5.0)["answered"] is True

		agent.result("bye")
	finally:
		agent.close()


@pytest.mark.slow
def test_an_unanswered_window_expires_and_the_session_survives() -> None:
	"""About five minutes against the add-on's shipped 300 s window, 30 s heartbeat, 120 s watchdog."""
	agent = _dial()
	try:
		_hello(agent, "silent")
		agent.result(
			"announce",
			text=(
				"Starting the slow checklist run. I will open a question and deliberately "
				"never answer it, for about five minutes, announcing as I go. Nothing is "
				"needed from you."
			),
		)

		ticket = agent.result("askUser", prompt="Slow test. Do not answer this one.")["ticket"]
		started = time.monotonic()

		expired = False
		polls = 0
		while time.monotonic() - started < 420.0:
			polls += 1
			reply = agent.raw("waitForUserReply", reply_timeout=90.0, ticket=ticket, timeout=60.0)
			if reply.get("error") is not None:
				expired = True
				break
			assert reply["result"]["answered"] is False, (
				"the bridge reported an answer, but nothing acknowledged the prompt"
			)
			minutes = (time.monotonic() - started) / 60.0
			agent.result("announce", text=f"Still waiting. {minutes:.0f} minutes so far.")

		elapsed = time.monotonic() - started
		assert expired, (
			f"the window was still open after {elapsed:.0f}s and {polls} polls; it should close at 300s"
		)
		assert elapsed >= 290.0, (
			f"the window closed after only {elapsed:.0f}s -- far short of its 300 s deadline, "
			"so something other than the deadline ended it"
		)

		before = agent.result("getNextSpeechIndex")["index"]
		agent.result("pressGesture", gestures=[SPEAKING_GESTURE])
		time.sleep(0.5)
		after = agent.result("getNextSpeechIndex")["index"]
		assert after > before, "nothing was captured after the window expired, so suppression never resumed"

		agent.result(
			"announce",
			text=f"Slow run finished. The window expired on its own after {elapsed:.0f} seconds.",
		)
		agent.result("bye")
	finally:
		agent.close()
