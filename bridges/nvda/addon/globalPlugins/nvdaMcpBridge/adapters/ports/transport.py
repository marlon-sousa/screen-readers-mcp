# nvdaMcpBridge adapters -- the Transport seam.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter seam for a raw byte pipe.
# USED BY: adapters/json_lines_channel.py.
# IMPLEMENTED BY: adapters/socket_transport.py, adapters/named_pipe_transport.py and tests/fakes/transport.py.

from __future__ import annotations

from abc import ABC, abstractmethod


class Transport(ABC):
	@abstractmethod
	def recv(self) -> bytes:
		"""Next chunk; ``b""`` at EOF; raises TimeoutError when idle."""

	@abstractmethod
	def sendall(self, data: bytes) -> None: ...

	@abstractmethod
	def close(self) -> None: ...
