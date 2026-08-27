# Integration scenario: a whole session over a REAL socket, headless.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# The 9a connection stack proven end to end: a real TcpListener on an ephemeral
# loopback port + BridgeServer + a FakeAdapterFactory, with a client socket
# dialling in and speaking raw protocol over its own SocketTransport +
# JsonLinesChannel. Everything below the NVDA edge is real -- the accept loop,
# the framing, the dispatch, the teardown -- so this runs in CI exactly like the
# loopback roundtrip, just over TCP instead of a queue. It is what proves the
# server the plugin will build in 9c actually works, and that sessions run
# sequentially against one server.

from __future__ import annotations

import socket
import struct
import time
from pathlib import Path
from typing import Any

from fakes.adapter_factory import FakeAdapterFactory
from fakes.announcer import FakeAnnouncer
from fakes.gesture_resolver import FakeGestureResolver
from fakes.log_capture import FakeLogCapture
from fakes.session_signals import FakeSessionSignals
from fakes.user_prompter import FakeUserPrompter
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.adapters.bridge_server import BridgeServer, ServerState
from nvdaMcpBridge.adapters.json_lines_channel import JsonLinesChannel
from nvdaMcpBridge.adapters.socket_transport import SocketTransport
from nvdaMcpBridge.adapters.tcp_listener import TcpListener
from nvdaMcpBridge.domain.controllers.commands.registry import NVDA_CAPABILITIES
from nvdaMcpBridge.domain.controllers.session import Session
from nvdaMcpBridge.wiring import build_session
from support.roundtrip import read_reply, request, wait_until


def _dial(endpoint: str | None) -> JsonLinesChannel:
	assert endpoint is not None
	host, port = endpoint.rsplit(":", 1)
	client = socket.create_connection((host, int(port)), timeout=5.0)
	return JsonLinesChannel(SocketTransport(client))


def test_a_whole_session_over_a_real_socket(tmp_path: Path) -> None:
	factories: list[FakeAdapterFactory] = []

	def session_factory(transport: Any) -> Session:
		# A fresh fake NVDA per session; kept so the test can assert capture was
		# stopped (the filter unregistered) on each teardown.
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

	listener = TcpListener("127.0.0.1", 0)
	server = BridgeServer(listener, session_factory)
	server.start()
	try:
		assert server.status.state is ServerState.LISTENING
		endpoint = server.status.endpoint

		# -- first session ---------------------------------------------------
		agent = _dial(endpoint)
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
			# Spec 0025: the gesture reply already carries what it caused, so the
			# act/settle/listen loop is one round trip here rather than three. The
			# settle and the read below still run because both commands still
			# exist -- they are just no longer how you learn what a key said.
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
			# One entry per utterance since spec 0021, not a joined blob.
			entries = read_reply(agent, awaiting="getSpeech (id 5)")["result"]["entries"]
			assert any("Elements list dialog" in entry["text"] for entry in entries)

			agent.write(request(6, "bye"))
			assert read_reply(agent, awaiting="bye")["result"] == {"ok": True}
		finally:
			agent.close()

		# The session ended (bye) and the server is accepting again, no restart.
		wait_until(
			lambda: server.status.state is ServerState.LISTENING,
			awaiting="the server to accept again",
		)
		assert factories[0].speech_source.stopped == 1

		# -- second session, same server -------------------------------------
		agent = _dial(endpoint)
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
	# A server that never sees a connection still stops cleanly and promptly --
	# the accept poll window, not a client, is what bounds stop().
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

	server = BridgeServer(TcpListener("127.0.0.1", 0), session_factory)
	server.start()
	started = time.monotonic()
	server.stop()
	assert time.monotonic() - started < 2.0
	assert server.status.state is ServerState.STOPPED


def test_an_abruptly_reset_client_does_not_kill_the_server(tmp_path: Path) -> None:
	# Regression: a client that crashes mid-session resets the connection (RST /
	# WinError 10054). The server must treat that as EOF, end the session, and
	# keep serving -- not let the exception take the accept loop down.
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

	server = BridgeServer(TcpListener("127.0.0.1", 0), session_factory)
	server.start()
	try:
		endpoint = server.status.endpoint
		assert endpoint is not None
		host, port = endpoint.rsplit(":", 1)

		# Open a session, then abort the connection with a RST (SO_LINGER 0).
		raw = socket.create_connection((host, int(port)), timeout=5.0)
		agent = JsonLinesChannel(SocketTransport(raw))
		agent.write(request(1, "hello", mode="silent", protocolVersion=p.PROTOCOL_VERSION))
		read_reply(agent, awaiting="hello")
		raw.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
		raw.close()  # -> RST to the bridge

		# The server survives: back to LISTENING, and a fresh session still works.
		wait_until(
			lambda: server.status.state is ServerState.LISTENING,
			awaiting="the server to accept again",
			timeout=5.0,
		)
		agent2 = _dial(endpoint)
		try:
			agent2.write(request(1, "hello", mode="silent", protocolVersion=p.PROTOCOL_VERSION))
			assert read_reply(agent2, awaiting="hello")["result"]["mode"] == "silent"
			agent2.write(request(2, "bye"))
			assert read_reply(agent2, awaiting="bye")["result"] == {"ok": True}
		finally:
			agent2.close()
	finally:
		server.stop()
