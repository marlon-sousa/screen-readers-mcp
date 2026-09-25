# nvdaMcpBridge domain entities -- bridge event types and DTOs.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: entity, the event types and the BridgeEvent DTO the EventBus port carries.

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from typing import Any


class BridgeEventType(StrEnum):
	SERVER_STATUS = "server-status"


@dataclass(frozen=True)
class BridgeEvent:
	"""The payload's shape is determined by the event type."""

	type: BridgeEventType
	payload: Any = None
