# nvdaMcpBridge domain -- GestureResolver: what keys the reader is ACTUALLY on.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port, reporting which gestures are bound to the boundary commands on this machine right now.
# IMPLEMENTED BY: adapters/nvda_gesture_resolver.py.
# USED BY: domain/entities/reader_guidance.py.
# Never substitute documented defaults: a remapped gesture does not fail, it silently does something else.

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol, runtime_checkable

# Named by the domain, not NVDA. The first three reach what the keyboard cannot; "reading" only re-reads.
GROUP_OBJECT_NAVIGATION = "object-navigation"
GROUP_TEXT_REVIEW = "text-review"
GROUP_MOUSE = "mouse"
GROUP_READING = "reading"

# In the order a document presents them.
ALL_GROUPS: tuple[str, ...] = (
	GROUP_READING,
	GROUP_OBJECT_NAVIGATION,
	GROUP_TEXT_REVIEW,
	GROUP_MOUSE,
)


@dataclass(frozen=True)
class ResolvedCommand:
	# Localised: the reader's own description.
	name: str

	# Stable and untranslated, so a finding can name the command after a rebind or a language change.
	script: str

	# Empty is a real answer: the command exists and nothing is bound to it.
	gestures: list[str] = field(default_factory=lambda: [])


@runtime_checkable
class GestureResolver(Protocol):
	def resolve(self) -> dict[str, list[ResolvedCommand]]:
		"""A snapshot of the moment; a group the reader cannot answer for maps to an empty list."""
		...
