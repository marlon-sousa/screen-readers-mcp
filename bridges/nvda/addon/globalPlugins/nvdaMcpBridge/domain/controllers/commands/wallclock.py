# nvdaMcpBridge domain -- rendering a wall-clock stamp for the wire.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: a pure function rendering an epoch float as the protocol's one wall-clock string shape.
# USED BY: get_log_position and the speech and braille reads.

from __future__ import annotations

from datetime import datetime

_MICROSECONDS_TO_MILLISECONDS = -3


def format_wallclock(epoch: float) -> str:
	"""``0.0`` is the buffers' "no instant recorded" sentinel and renders as the empty string."""
	if not epoch:
		return ""
	return datetime.fromtimestamp(epoch).strftime("%Y-%m-%d %H:%M:%S.%f")[:_MICROSECONDS_TO_MILLISECONDS]
