# Live-NVDA end-to-end scenario: drive the real bridge over the loopback socket.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# Dials the real NVDA and installed add-on on 127.0.0.1:DEFAULT_PORT; every test skips when nothing listens.

from __future__ import annotations

import socket
import time
from typing import Any

import pytest

#: Drives a real NVDA on this machine; excluded from the default run.
pytestmark = pytest.mark.live_nvda

from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.adapters.json_lines_channel import JsonLinesChannel
from nvdaMcpBridge.adapters.socket_transport import SocketTransport
from nvdaMcpBridge.domain.controllers.commands.registry import NVDA_CAPABILITIES
from nvdaMcpBridge.domain.ports.message_channel import Timeout

HOST = "127.0.0.1"

#: Speaks in essentially any focus context, so capture does not depend on the open window.
SPEAKING_GESTURE = "NVDA+t"


@pytest.fixture(scope="module", autouse=True)
def require_live_bridge() -> None:
	try:
		socket.create_connection((HOST, p.DEFAULT_PORT), timeout=0.5).close()
	except OSError:
		pytest.skip(
			f"no bridge on {HOST}:{p.DEFAULT_PORT} -- start NVDA with the nvdaMcpBridge addon installed"
		)


class Agent:
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
		sock = socket.create_connection((HOST, p.DEFAULT_PORT), timeout=1.0)
	except OSError:
		pytest.skip(
			f"no bridge on {HOST}:{p.DEFAULT_PORT} -- start NVDA with the nvdaMcpBridge addon installed"
		)
	return Agent(JsonLinesChannel(SocketTransport(sock)))


def _hello(agent: Agent, mode: str) -> dict[str, Any]:
	return agent.result("hello", mode=mode, protocolVersion=p.PROTOCOL_VERSION)


def _spoken(speech: dict[str, Any]) -> str:
	return "\n".join(entry["text"] for entry in speech["entries"])


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
		# Silent-mode finish is the buffer's one-second elapsed heuristic; give it the window.
		assert agent.result("waitForSpeechToFinish", timeout=3.0)["finished"] is True
		speech = agent.result("getSpeech", sinceIndex=start)
		assert _spoken(speech).strip(), "the gesture should have been captured as speech"
		assert speech["toIndex"] > speech["fromIndex"]
		assert all(entry["logPosition"] >= 0 for entry in speech["entries"])
		agent.result("bye")
	finally:
		agent.close()


def test_the_synth_stays_the_real_one_across_sessions() -> None:
	first = _dial()
	try:
		real_synth = _hello(first, "silent")["synth"]
		first.result("bye")
	finally:
		first.close()

	second = _dial()
	try:
		assert _hello(second, "silent")["synth"] == real_synth
		assert real_synth  # a real synth name, never empty
		second.result("bye")
	finally:
		second.close()


def test_announce_is_acked_in_silent_mode() -> None:
	agent = _dial()
	try:
		_hello(agent, "silent")
		assert agent.result("announce", text="nvda mcp bridge announce test") == {"ok": True}
		agent.result("bye")
	finally:
		agent.close()


def test_live_session_captures_without_swapping() -> None:
	agent = _dial()
	try:
		hello = _hello(agent, "live")
		assert hello["mode"] == "live"
		start = agent.result("getNextSpeechIndex")["index"]
		agent.result("pressGesture", gestures=[SPEAKING_GESTURE])
		agent.result("waitForSpeechToFinish", timeout=3.0)
		assert _spoken(agent.result("getSpeech", sinceIndex=start)).strip()
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
