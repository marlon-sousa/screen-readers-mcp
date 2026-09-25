# nvdaMcpBridge domain ports -- the EventBus port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port, a pub/sub channel shared by the domain and adapters.
# IMPLEMENTED BY: adapters/simple_event_bus.py.
# USED BY: BridgeServer as emitter and BridgeDialog as subscriber.

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Callable

from ..entities.bridge_events import BridgeEvent, BridgeEventType

EventHandler = Callable[[BridgeEvent], None]

SubscriptionToken = str


class EventBus(ABC):
	"""Handlers run synchronously on the publishing thread; a UI handler must marshal itself."""

	@abstractmethod
	def subscribe(self, event_type: BridgeEventType, handler: EventHandler) -> SubscriptionToken:
		"""Returns a token for unsubscribe()."""

	@abstractmethod
	def unsubscribe(self, token: SubscriptionToken) -> None:
		"""Safe to call when already removed."""

	@abstractmethod
	def emit(self, event: BridgeEvent) -> None:
		"""Deliver *event* to every handler registered for its type."""
