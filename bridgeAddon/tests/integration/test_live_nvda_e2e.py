# Live-NVDA end-to-end scenario: drive the REAL bridge over the loopback socket.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# This is the automated half of spec 0007's 9c checklist. Unlike the headless
# integration scenarios (which stand up an in-process BridgeServer), this dials
# the bridge that a real NVDA + installed addon is listening with on
# 127.0.0.1:DEFAULT_PORT, so it proves the REAL adapters -- the spy synth, the
# capture hooks, the fail-safe restore, the gesture injection -- behave like
# their fakes. It is the "only place that proves a real adapter behaves like its
# fake" AGENTS.md means by a live-NVDA scenario.
#
# It is NOT a CI test: when no bridge is listening (as in CI, or on any machine
# without NVDA running the addon) every test SKIPS at the dial. Run it locally
# with NVDA up and the addon installed:
#
#     uv run --directory bridgeAddon --with pytest pytest tests/integration/test_live_nvda_e2e.py -v
#
# It reuses the addon's own SocketTransport + JsonLinesChannel as the client
# side, exactly as the headless socket roundtrip does -- the wire is symmetric.
#
# Human-observable checklist items (NVDA actually goes quiet / talks again, the
# panic gesture's spoken confirmation, config-save/profile-switch defence) stay
# manual in the PR body; this file automates the programmatic contract: the
# handshake fields, capture, exact-finish, sequential sessions, and -- the one
# safety property it CAN prove over the wire -- that the real synth is restored
# after a session (a fresh hello reports the same real synth, never the spy).

from __future__ import annotations

import socket
import time
from typing import Any

import pytest

from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.adapters.json_lines_channel import JsonLinesChannel
from nvdaMcpBridge.adapters.socket_transport import SocketTransport
from nvdaMcpBridge.domain.ports.message_channel import Timeout

HOST = "127.0.0.1"

#: A gesture that speaks in essentially any focus context (reports the title),
#: so the capture assertion does not depend on a particular window being open.
#: The checklist's NVDA+f7 (elements list) is the manual, human-observed variant.
SPEAKING_GESTURE = "NVDA+t"

#: The spy must never be what a session reports as the user's synth.
SPY_SYNTH_NAME = "nvdaMcpSpy"


@pytest.fixture(scope="module", autouse=True)
def require_live_bridge() -> None:
	"""Probe once per module: if no bridge is listening, skip every test here.

	One connection attempt instead of one per test, so a machine without NVDA
	(CI included) spends a single short timeout, not several.
	"""
	try:
		socket.create_connection((HOST, p.DEFAULT_PORT), timeout=0.5).close()
	except OSError:
		pytest.skip(
			f"no bridge on {HOST}:{p.DEFAULT_PORT} -- start NVDA with the nvdaMcpBridge addon installed"
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
	"""Connect to the live bridge, or skip the test if nothing is listening."""
	try:
		sock = socket.create_connection((HOST, p.DEFAULT_PORT), timeout=1.0)
	except OSError:
		pytest.skip(
			f"no bridge on {HOST}:{p.DEFAULT_PORT} -- start NVDA with the nvdaMcpBridge addon installed"
		)
	return Agent(JsonLinesChannel(SocketTransport(sock)))


def _hello(agent: Agent, mode: str) -> dict[str, Any]:
	return agent.result("hello", mode=mode, protocolVersion=p.PROTOCOL_VERSION)


# -- handshake (checklist 1, 5) ----------------------------------------------


def test_hello_reports_real_nvda_and_served_capabilities() -> None:
	agent = _dial()
	try:
		hello = _hello(agent, "silent")
		assert hello["reader"]["name"] == "nvda"
		assert hello["reader"]["version"], "reader.version should match About NVDA"
		assert hello["capabilities"] == [
			c.value for c in (p.Capability.SPEECH, p.Capability.BRAILLE, p.Capability.GESTURES)
		]
		assert hello["mode"] == "silent"
		assert hello["synth"] and hello["synth"] != SPY_SYNTH_NAME
		agent.result("bye")
	finally:
		agent.close()


# -- silent capture + exact finish (checklist 2) -----------------------------


def test_silent_session_captures_a_gesture_and_finishes() -> None:
	agent = _dial()
	try:
		_hello(agent, "silent")
		start = agent.result("getNextSpeechIndex")["index"]
		assert agent.result("pressGesture", gestures=[SPEAKING_GESTURE]) == {"ok": True}
		# Exact-finish is driven by the spy's synthDoneSpeaking, so this returns
		# as soon as the spy stops -- promptly, not on the timeout.
		assert agent.result("waitForSpeechToFinish", timeout=5.0)["finished"] is True
		speech = agent.result("getSpeech", sinceIndex=start)
		assert speech["text"].strip(), "the gesture should have been captured as speech"
		assert speech["toIndex"] > speech["fromIndex"]
		agent.result("bye")
	finally:
		agent.close()


# -- the safety property we can prove over the wire (checklist 2/3) -----------


def test_the_real_synth_is_restored_after_a_silent_session() -> None:
	first = _dial()
	try:
		real_synth = _hello(first, "silent")["synth"]
		first.result("bye")
	finally:
		first.close()

	# A brand-new session must still see the user's real synth. If restore had
	# leaked the spy into config, this second hello would report nvdaMcpSpy.
	second = _dial()
	try:
		assert _hello(second, "silent")["synth"] == real_synth
		assert real_synth != SPY_SYNTH_NAME
		second.result("bye")
	finally:
		second.close()


# -- live mode (checklist 4) --------------------------------------------------


def test_live_session_captures_without_swapping() -> None:
	agent = _dial()
	try:
		hello = _hello(agent, "live")
		assert hello["mode"] == "live"
		start = agent.result("getNextSpeechIndex")["index"]
		agent.result("pressGesture", gestures=[SPEAKING_GESTURE])
		# Live mode has no exact-finish signal; the buffer's elapsed-time
		# heuristic decides, so allow it the full window.
		agent.result("waitForSpeechToFinish", timeout=5.0)
		assert agent.result("getSpeech", sinceIndex=start)["text"].strip()
		agent.result("bye")
	finally:
		agent.close()


# -- sequential sessions against one server (checklist 7) ---------------------


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
	assert synths[0] != SPY_SYNTH_NAME
