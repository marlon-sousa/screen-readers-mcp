# nvdaMcpBridge adapters -- TcpListener: the Listener leaf.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: leaf adapter implementing Listener with a TCP socket.
# BUILT BY: adapters/build_listener.py.
# USED BY: adapters/bridge_server.py, through the Listener seam.
# Binds loopback only: remote TCP would be remote keystroke injection and config writes.

from __future__ import annotations

import socket

from .ports.listener import Listener, ListenerClosed
from .ports.transport import Transport
from .socket_transport import DEFAULT_POLL_TIMEOUT, SocketTransport

DEFAULT_ACCEPT_TIMEOUT: float = 0.5


class TcpListener(Listener):
	def __init__(
		self,
		host: str,
		port: int,
		*,
		accept_timeout: float = DEFAULT_ACCEPT_TIMEOUT,
		recv_timeout: float = DEFAULT_POLL_TIMEOUT,
	) -> None:
		self._host = host
		self._port = port
		self._accept_timeout = accept_timeout
		self._recv_timeout = recv_timeout
		self._sock: socket.socket | None = None
		self._endpoint = f"{host}:{port}"
		self._closed = False

	@property
	def endpoint(self) -> str:
		return self._endpoint

	def open(self) -> None:
		sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
		sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
		sock.bind((self._host, self._port))
		sock.listen(1)
		sock.settimeout(self._accept_timeout)
		# The bound port is only known now when the caller asked for port 0.
		bound_host, bound_port = sock.getsockname()[:2]
		self._endpoint = f"{bound_host}:{bound_port}"
		self._sock = sock

	def accept(self) -> Transport:
		if self._sock is None or self._closed:
			raise ListenerClosed
		try:
			conn, _ = self._sock.accept()
		except OSError:
			if self._closed:
				raise ListenerClosed from None
			raise
		return SocketTransport(conn, poll_timeout=self._recv_timeout)

	def close(self) -> None:
		self._closed = True
		sock = self._sock
		self._sock = None
		if sock is not None:
			sock.close()
