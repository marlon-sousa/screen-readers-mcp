# nvdaMcpBridge adapters -- build_listener: the single mode→Listener factory.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: a pure factory function mapping a ConnectionMode to its Listener leaf.
# USED BY: plugin.py and views/bridge_dialog.py.

from __future__ import annotations

from .. import protocol
from ..domain.entities.connection_mode import ConnectionMode
from .named_pipe_listener import NamedPipeListener
from .ports.listener import Listener
from .tcp_listener import TcpListener


def build_listener(mode: ConnectionMode) -> Listener:
	if mode is ConnectionMode.NAMED_PIPE:
		return NamedPipeListener(protocol.DEFAULT_PIPE_NAME)
	if mode is ConnectionMode.LOOPBACK_TCP:
		return TcpListener("127.0.0.1", protocol.DEFAULT_PORT)
	raise ValueError(f"Unsupported connection mode: {mode}")
