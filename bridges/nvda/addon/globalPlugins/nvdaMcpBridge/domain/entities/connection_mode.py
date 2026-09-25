# nvdaMcpBridge domain -- ConnectionMode: the transport the bridge listens on.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: entity, the transport the bridge listens on; the wire does not know about transports.
# USED BY: the BridgeConfig port and its ini adapter, the bridge dialog, and plugin.py.

from __future__ import annotations

from enum import StrEnum
from typing import Final


class ConnectionMode(StrEnum):
	NAMED_PIPE = "namedPipe"
	LOOPBACK_TCP = "loopbackTcp"
	REMOTE_TCP = "remoteTcp"  # defined but unreachable from the UI until its security entry lands


DEFAULT: Final = ConnectionMode.NAMED_PIPE
