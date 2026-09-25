# nvdaMcpBridge tests -- LoopbackTransport, a connected pair of Transport ends.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import queue

from nvdaMcpBridge.adapters.ports.transport import Transport


class _Eof:
	__slots__ = ()


_EOF = _Eof()


class LoopbackTransport(Transport):
	def __init__(
		self,
		incoming: queue.Queue[bytes | _Eof],
		outgoing: queue.Queue[bytes | _Eof],
		*,
		poll_timeout: float = 0.05,
	) -> None:
		self._incoming = incoming
		self._outgoing = outgoing
		self._poll_timeout = poll_timeout
		self._eof = False

	def recv(self) -> bytes:
		if self._eof:
			return b""
		try:
			item = self._incoming.get(timeout=self._poll_timeout)
		except queue.Empty:
			raise TimeoutError from None
		if isinstance(item, _Eof):
			self._eof = True
			return b""
		return item

	def sendall(self, data: bytes) -> None:
		self._outgoing.put(data)

	def close(self) -> None:
		self._outgoing.put(_EOF)


def loopback_pair(*, poll_timeout: float = 0.05) -> tuple[LoopbackTransport, LoopbackTransport]:
	"""A (bridge, agent) pair: each end's writes are the other's reads."""
	a_to_b: queue.Queue[bytes | _Eof] = queue.Queue()
	b_to_a: queue.Queue[bytes | _Eof] = queue.Queue()
	bridge = LoopbackTransport(incoming=a_to_b, outgoing=b_to_a, poll_timeout=poll_timeout)
	agent = LoopbackTransport(incoming=b_to_a, outgoing=a_to_b, poll_timeout=poll_timeout)
	return bridge, agent
