# nvdaMcpBridge adapters -- SocketTransport: the Transport leaf.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: leaf adapter implementing Transport over one connected TCP socket.
# BUILT BY: adapters/tcp_listener.py.
# USED BY: adapters/json_lines_channel.py, through the Transport seam.

from __future__ import annotations

import socket

from .ports.transport import Transport

DEFAULT_POLL_TIMEOUT: float = 0.05


class SocketTransport(Transport):
	def __init__(self, sock: socket.socket, *, poll_timeout: float = DEFAULT_POLL_TIMEOUT) -> None:
		self._sock = sock
		self._sock.settimeout(poll_timeout)

	def recv(self) -> bytes:
		"""Any socket error but a timeout, such as a killed client's reset, is EOF, so the loop survives."""
		try:
			return self._sock.recv(4096)
		except TimeoutError:
			raise
		except OSError:
			return b""

	def sendall(self, data: bytes) -> None:
		self._sock.sendall(data)

	def close(self) -> None:
		self._sock.close()
