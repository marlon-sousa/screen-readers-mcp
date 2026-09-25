# nvdaMcpBridge domain -- SilenceCap: how long the human has been unable to hear.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: entity, the silence-cap watchdog's pure model of how long the human has been unable to hear.
# BUILT BY: the Session, when a silent session establishes on a machine not declared unattended.
# USED BY: the Session's ``_check_silence``, which acts on each returned action.
# Only sound the human actually hears may reset it; gestures and reads never do.

from __future__ import annotations

import enum
from dataclasses import dataclass

# Not shorter: NVDA 2026.1 emits speech some five seconds ahead of the audio.
DEFAULT_WARN_AFTER: float = 45.0
DEFAULT_LIFT_AFTER: float = 90.0


@dataclass(frozen=True)
class SilenceCapPolicy:
	"""Frozen, and never settable over the wire. Defaults to attended, the safe direction."""

	enabled: bool
	warn_after: float = DEFAULT_WARN_AFTER
	lift_after: float = DEFAULT_LIFT_AFTER

	def __post_init__(self) -> None:
		# Checked here: a warning after the lift would silently never be spoken.
		if not 0 < self.warn_after < self.lift_after:
			raise ValueError(
				f"silence cap thresholds must satisfy 0 < warn < lift; "
				f"got warn_after={self.warn_after!r}, lift_after={self.lift_after!r}"
			)

	@classmethod
	def from_settings(cls, *, unattended: bool, warn_after: float, lift_after: float) -> SilenceCapPolicy:
		"""A crossed pair from the config file falls back to the defaults, never to no cap."""
		try:
			return cls(enabled=not unattended, warn_after=warn_after, lift_after=lift_after)
		except ValueError:
			return cls(enabled=not unattended)


ATTENDED_DEFAULT = SilenceCapPolicy(enabled=True)


class SilenceCapAction(enum.Enum):
	NONE = "none"
	WARN = "warn"
	# Capture continues after a lift.
	LIFT = "lift"


class SilenceCap:
	"""Each of WARN and LIFT is returned at most once per window."""

	def __init__(self, policy: SilenceCapPolicy, now: float) -> None:
		self._policy = policy
		self._since = now
		self._warned = False
		self._lifted = False
		self._paused_at: float | None = None

	@property
	def policy(self) -> SilenceCapPolicy:
		return self._policy

	@property
	def lifted(self) -> bool:
		return self._lifted

	@property
	def is_paused(self) -> bool:
		return self._paused_at is not None

	def heard(self, now: float) -> None:
		self._since = now
		self._warned = False

	def paused(self, now: float) -> None:
		"""Idempotent."""
		if self._paused_at is None:
			self._paused_at = now

	def resumed(self, now: float) -> None:
		"""Idempotent; the paused span is not charged to the window."""
		if self._paused_at is None:
			return
		self._since += now - self._paused_at
		self._paused_at = None

	def resuppressed(self, now: float) -> None:
		self._lifted = False
		self._warned = False
		self._since = now

	def check(self, now: float) -> SilenceCapAction:
		"""Never raises, and never repeats an act."""
		if not self._policy.enabled or self._lifted or self._paused_at is not None:
			return SilenceCapAction.NONE
		elapsed = now - self._since
		# The lift is tested first: it is the guarantee, and the warning only a courtesy.
		if elapsed >= self._policy.lift_after:
			self._lifted = True
			self._warned = True
			return SilenceCapAction.LIFT
		if not self._warned and elapsed >= self._policy.warn_after:
			self._warned = True
			return SilenceCapAction.WARN
		return SilenceCapAction.NONE
