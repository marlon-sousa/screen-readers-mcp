# nvdaMcpBridge tests -- FakeTransport, standing in for the Transport seam.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.adapters.ports.transport import Transport

from .script import ClosedEvent, ScriptedQueue, TimeoutEvent

if TYPE_CHECKING:
	from .clock import FakeClock


class FakeTransport(Transport):
	"""Script entries: bytes are one recv, TIMEOUT_EVENT raises TimeoutError, CLOSED_EVENT returns b""."""

	def __init__(
		self,
		events: list[Any] | None = None,
		*,
		clock: FakeClock | None = None,
		timeout_advance: float = 5.0,
		on_empty: str = "closed",
	) -> None:
		self._queue = ScriptedQueue(list(events or []), clock, timeout_advance, on_empty)
		self.outbox = bytearray()
		self.closed = False

	def recv(self) -> bytes:
		event = self._queue.next_event()
		if isinstance(event, TimeoutEvent):
			self._queue.tick_timeout()
			raise TimeoutError
		if isinstance(event, ClosedEvent):
			return b""
		assert isinstance(event, (bytes, bytearray))
		return bytes(event)

	def sendall(self, data: bytes) -> None:
		self.outbox.extend(data)

	def close(self) -> None:
		self.closed = True

	def responses(self) -> list[dict[str, Any]]:
		lines = bytes(self.outbox).splitlines()
		return [p.decode_message(line) for line in lines if line]
