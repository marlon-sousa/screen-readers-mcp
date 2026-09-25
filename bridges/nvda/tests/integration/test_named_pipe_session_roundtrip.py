# Integration scenario: a whole session over a real named pipe, headless.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from support.platforms import skip_module_unless_windows

# Must precede every import below; see tests/support/platforms.py.
skip_module_unless_windows("a whole session over a REAL named pipe, which is a Win32 facility")

import time
import uuid
from pathlib import Path
from typing import Any

from fakes.adapter_factory import FakeAdapterFactory
from fakes.announcer import FakeAnnouncer
from fakes.gesture_resolver import FakeGestureResolver
from fakes.log_capture import FakeLogCapture
from fakes.session_signals import FakeSessionSignals
from fakes.user_prompter import FakeUserPrompter
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.adapters import named_pipe_transport
from nvdaMcpBridge.adapters.bridge_server import BridgeServer, ServerState
from nvdaMcpBridge.adapters.json_lines_channel import JsonLinesChannel
from nvdaMcpBridge.adapters.named_pipe_listener import NamedPipeListener
from nvdaMcpBridge.domain.controllers.commands.registry import NVDA_CAPABILITIES
from nvdaMcpBridge.domain.controllers.session import Session
from nvdaMcpBridge.wiring import build_session
from support.roundtrip import read_reply, request, wait_until


def _unique_pipe_name() -> str:
	# A fresh name per test, so parallel runs and a live bridge on DEFAULT_PIPE_NAME never collide.
	return rf"\\.\pipe\nvdaMcpBridge-test-{uuid.uuid4()}"


def _dial(pipe_name: str) -> JsonLinesChannel:
	return JsonLinesChannel(named_pipe_transport.dial(pipe_name))


def test_a_whole_session_over_a_real_named_pipe(tmp_path: Path) -> None:
	factories: list[FakeAdapterFactory] = []

	def session_factory(transport: Any) -> Session:
		factory = FakeAdapterFactory(speech={"NVDA+f7": ["Elements list dialog"]})
		factories.append(factory)
		return build_session(
			transport,
			factory,
			tmp_path,
			"2026.1.0",
			FakeSessionSignals(),
			FakeAnnouncer(),
			FakeLogCapture(),
			FakeUserPrompter(),
			FakeGestureResolver(),
		)

	pipe_name = _unique_pipe_name()
	listener = NamedPipeListener(pipe_name)
	server = BridgeServer(listener, session_factory)
	server.start()
	try:
		assert server.status.state is ServerState.LISTENING
		assert server.status.endpoint == pipe_name

		agent = _dial(pipe_name)
		try:
			agent.write(request(1, "hello", mode="silent", protocolVersion=p.PROTOCOL_VERSION))
			hello = read_reply(agent, awaiting="hello")
			assert hello["result"]["mode"] == "silent"
			assert hello["result"]["reader"] == {"name": "nvda", "version": "2026.1.0"}
			assert hello["result"]["capabilities"] == [c.value for c in NVDA_CAPABILITIES]

			payload = {"u": "olá café \U0001f600", "nested": [1, 2, {"x": True}]}
			agent.write(request(2, "echo", payload=payload))
			assert read_reply(agent, awaiting="echo (id 2)")["result"]["payload"] == payload

			agent.write(request(3, "pressGesture", gestures=["NVDA+f7"]))
			pressed = read_reply(agent, awaiting="pressGesture (id 3)")["result"]
			assert [p["gesture"] for p in pressed["pressed"]] == ["NVDA+f7"]
			assert any("Elements list dialog" in e["text"] for e in pressed["speech"])
			assert pressed["speechTo"] > pressed["speechFrom"]
			assert pressed["state"]["speechMode"] == "talk"
			agent.write(request(4, "waitForSpeechToFinish", timeout=3.0))
			assert (
				read_reply(agent, awaiting="waitForSpeechToFinish (id 4)", polls=120)["result"]["finished"]
				is True
			)
			agent.write(request(5, "getSpeech", sinceIndex=0))
			entries = read_reply(agent, awaiting="getSpeech (id 5)")["result"]["entries"]
			assert any("Elements list dialog" in entry["text"] for entry in entries)

			agent.write(request(6, "bye"))
			assert read_reply(agent, awaiting="bye")["result"] == {"ok": True}
		finally:
			agent.close()

		wait_until(
			lambda: server.status.state is ServerState.LISTENING,
			awaiting="the server to accept again",
		)
		assert factories[0].speech_source.stopped == 1

		agent = _dial(pipe_name)
		try:
			agent.write(request(1, "hello", mode="silent", protocolVersion=p.PROTOCOL_VERSION))
			assert read_reply(agent, awaiting="hello")["result"]["mode"] == "silent"
			agent.write(request(2, "bye"))
			assert read_reply(agent, awaiting="bye")["result"] == {"ok": True}
		finally:
			agent.close()

		wait_until(
			lambda: server.status.state is ServerState.LISTENING,
			awaiting="the server to accept again",
		)
		assert len(factories) == 2
		assert factories[1].speech_source.stopped == 1
	finally:
		server.stop()

	assert server.status.state is ServerState.STOPPED


def test_stop_ends_an_idle_server_promptly(tmp_path: Path) -> None:
	def session_factory(transport: Any) -> Session:
		return build_session(
			transport,
			FakeAdapterFactory(),
			tmp_path,
			"2026.1.0",
			FakeSessionSignals(),
			FakeAnnouncer(),
			FakeLogCapture(),
			FakeUserPrompter(),
			FakeGestureResolver(),
		)

	server = BridgeServer(NamedPipeListener(_unique_pipe_name()), session_factory)
	server.start()
	started = time.monotonic()
	server.stop()
	assert time.monotonic() - started < 2.0
	assert server.status.state is ServerState.STOPPED


def test_an_abruptly_closed_client_does_not_kill_the_server(tmp_path: Path) -> None:
	def session_factory(transport: Any) -> Session:
		return build_session(
			transport,
			FakeAdapterFactory(),
			tmp_path,
			"2026.1.0",
			FakeSessionSignals(),
			FakeAnnouncer(),
			FakeLogCapture(),
			FakeUserPrompter(),
			FakeGestureResolver(),
		)

	pipe_name = _unique_pipe_name()
	server = BridgeServer(NamedPipeListener(pipe_name), session_factory)
	server.start()
	try:
		agent = _dial(pipe_name)
		agent.write(request(1, "hello", mode="silent", protocolVersion=p.PROTOCOL_VERSION))
		read_reply(agent, awaiting="hello")
		agent.close()  # no `bye` -- just vanish

		wait_until(
			lambda: server.status.state is ServerState.LISTENING,
			awaiting="the server to accept again",
			timeout=5.0,
		)
		agent2 = _dial(pipe_name)
		try:
			agent2.write(request(1, "hello", mode="silent", protocolVersion=p.PROTOCOL_VERSION))
			assert read_reply(agent2, awaiting="hello")["result"]["mode"] == "silent"
			agent2.write(request(2, "bye"))
			assert read_reply(agent2, awaiting="bye")["result"] == {"ok": True}
		finally:
			agent2.close()
	finally:
		server.stop()


def test_a_client_that_vanishes_with_a_prompt_open_leaves_speech_on(tmp_path: Path) -> None:
	# A client dying with a prompt open must not leave the filter reinstalled, or the tester is left mute.
	factories: list[FakeAdapterFactory] = []
	prompters: list[FakeUserPrompter] = []

	def session_factory(transport: Any) -> Session:
		factory = FakeAdapterFactory()
		prompter = FakeUserPrompter()
		factories.append(factory)
		prompters.append(prompter)
		return build_session(
			transport,
			factory,
			tmp_path,
			"2026.1.0",
			FakeSessionSignals(),
			FakeAnnouncer(),
			FakeLogCapture(),
			prompter,
			FakeGestureResolver(),
		)

	pipe_name = _unique_pipe_name()
	server = BridgeServer(NamedPipeListener(pipe_name), session_factory)
	server.start()
	try:
		agent = _dial(pipe_name)
		agent.write(request(1, "hello", mode="silent", protocolVersion=p.PROTOCOL_VERSION))
		read_reply(agent, awaiting="hello")

		agent.write(request(2, "askUser", prompt="unplug the display and tell me"))
		ticket = read_reply(agent, awaiting="askUser (id 2)")["result"]["ticket"]
		assert factories[0].speech_source.suspended == 1
		assert factories[0].speech_source.stopped == 0

		agent.close()  # the agent dies mid-question -- no bye, no answer

		wait_until(
			lambda: server.status.state is ServerState.LISTENING,
			awaiting="the server to accept again",
			timeout=5.0,
		)
	finally:
		server.stop()

	assert factories[0].speech_source.stopped == 1
	# A resume() here would reinstall the filter and could strand the tester mute.
	assert factories[0].speech_source.resumed == 0
	assert prompters[0].cancelled == [ticket]


def test_accept_and_recv_report_timeout_when_idle() -> None:
	pipe_name = _unique_pipe_name()
	listener = NamedPipeListener(pipe_name, accept_timeout=0.2)
	listener.open()
	try:
		start = time.monotonic()
		try:
			listener.accept()
			raise AssertionError("expected TimeoutError")
		except TimeoutError:
			pass
		assert 0.15 < time.monotonic() - start < 1.0

		client = named_pipe_transport.dial(pipe_name)
		try:
			server_side = listener.accept()
			try:
				start = time.monotonic()
				try:
					server_side.recv()
					raise AssertionError("expected TimeoutError")
				except TimeoutError:
					pass
				assert 0.0 < time.monotonic() - start < 1.0

				client.sendall(b"hi")
				assert server_side.recv() == b"hi"
			finally:
				server_side.close()
		finally:
			client.close()
	finally:
		listener.close()
