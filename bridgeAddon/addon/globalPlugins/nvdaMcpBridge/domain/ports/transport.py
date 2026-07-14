# nvdaMcpBridge domain -- the Transport port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from abc import ABC, abstractmethod


class Transport(ABC):
	"""The raw byte pipe a :class:`~..framing.Connection` frames over.

	``recv`` returns the next chunk, ``b""`` at EOF, and raises ``TimeoutError``
	when no data arrived within its poll window (a real socket set with
	``settimeout`` already behaves exactly this way). The timeout is how the
	session periodically regains control to check its deadlines.
	"""

	@abstractmethod
	def recv(self) -> bytes: ...

	@abstractmethod
	def sendall(self, data: bytes) -> None: ...

	@abstractmethod
	def close(self) -> None: ...
