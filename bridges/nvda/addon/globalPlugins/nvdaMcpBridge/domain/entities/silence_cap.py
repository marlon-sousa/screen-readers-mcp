# nvdaMcpBridge domain -- SilenceCap: how long the human has been unable to hear.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: entity. The third watchdog's whole model (spec 0032), and PURE: no IO, no
# NVDA, no clock of its own -- every method takes ``now`` as a monotonic float, so
# the entire thing is testable with plain numbers.
# BUILT BY: the Session, once, when a SILENT session establishes on a capped
#           machine. There is no cap in live mode (nothing is suppressed) and none
#           on a machine whose owner declared it unattended.
# USED BY: the Session's ``_check_silence``, which turns each returned action into
#          a spoken notice and, at the lift, a call through the SpeechSource port.
#
# WHAT IT MEASURES, and why it is neither watchdog we already had. The heartbeat
# asks "is the harness PROCESS alive?" and command-inactivity asks "is the AGENT
# still testing?" -- both fire on ABSENCE, and both stayed correctly quiet on
# 2026-08-03 while a human sat mute for minutes and reached for the panic gesture.
# Twice. This one asks the human's question instead:
#
#     How long have I been unable to hear my own machine?
#
# Those readings come apart precisely when an agent is BUSY BUT SLOW, which after
# spec 0025 is the normal case rather than an edge one.
#
# WHAT RESETS IT is only sound the human actually hears. During suppression that
# is exactly the set of things reaching the synth past the speak() filter -- the
# session start cue, ``announce`` and ``askUser`` -- which is not a coincidence but
# the definition. Four hundred gestures in ninety seconds reset nothing, because
# they told the human nothing.
#
# It knows nothing about speech sources, announcers or NVDA. It answers "given
# these instants, what should happen"; the Session does it.

from __future__ import annotations

import enum
from dataclasses import dataclass

#: The shipped thresholds, in seconds. Early enough that the warning lands before
#: a human starts wondering whether the machine has died, long enough that a
#: normally narrated run never hears it. They are deliberately NOT shorter: spec
#: 0032 Part 9 and protocol.md section 7.1 measured speech EMISSION running some
#: five seconds ahead of audio, so an ``announce`` that resets this clock has been
#: made rather than necessarily heard -- a rounding error at 45 s, and not one at
#: 5 s.
DEFAULT_WARN_AFTER: float = 45.0
DEFAULT_LIFT_AFTER: float = 90.0


@dataclass(frozen=True)
class SilenceCapPolicy:
	"""Whether a machine bounds its silences, and by how much.

	Built by ``plugin.py`` from :class:`BridgeConfig` and carried on
	``SessionConfig``. Frozen because it is settled before the session starts and
	nothing on the wire may change it: an agent that could raise its own ceiling
	does not have one.

	``enabled`` is False on a machine whose owner ticked *unattended* -- an
	accessibility run on a CI box at 3am has no human to protect, and un-muting a
	session whose whole purpose was to run silently is damage rather than a
	safeguard. It defaults to attended, because the costs are not symmetric: a cap
	on an empty room speaks to nobody, and a missing cap on an occupied one leaves
	a blind person unable to hear their computer.
	"""

	enabled: bool
	warn_after: float = DEFAULT_WARN_AFTER
	lift_after: float = DEFAULT_LIFT_AFTER

	def __post_init__(self) -> None:
		# Ordering is checked HERE so a nonsensical pair cannot reach the loop,
		# where "warn after the lift" would mean the warning is never spoken and
		# nothing at all would look wrong.
		if not 0 < self.warn_after < self.lift_after:
			raise ValueError(
				f"silence cap thresholds must satisfy 0 < warn < lift; "
				f"got warn_after={self.warn_after!r}, lift_after={self.lift_after!r}"
			)

	@classmethod
	def from_settings(cls, *, unattended: bool, warn_after: float, lift_after: float) -> SilenceCapPolicy:
		"""Build a policy from persisted settings, tolerating an unordered pair.

		The constructor RAISES on an unordered pair, which is right for a
		programming error and wrong for a config file a human typed: two settings
		read independently can each look sane and still cross over. So the one
		caller that reads them off disk comes through here, and gets the shipped
		defaults plus the ``unattended`` choice it did understand.

		Failing toward the DEFAULTS rather than toward "no cap" is the same safe
		direction the whole entry takes: a machine nobody has configured coherently
		is not a machine we may assume is empty.
		"""
		try:
			return cls(enabled=not unattended, warn_after=warn_after, lift_after=lift_after)
		except ValueError:
			return cls(enabled=not unattended)


#: What a machine gets when nobody has configured it: capped, on the shipped
#: thresholds. The safe direction, and the single definition of it -- the Session's
#: default, wiring's fallback and the tests all read this one value, so they cannot
#: drift into disagreeing about what "unconfigured" means.
ATTENDED_DEFAULT = SilenceCapPolicy(enabled=True)


class SilenceCapAction(enum.Enum):
	"""What the session loop should do about the silence, right now."""

	#: Nothing is owed: either the window is young, or its notice already went out.
	NONE = "none"
	#: Speak the warning. The human learns the room is quiet with time to spare.
	WARN = "warn"
	#: Stop suppressing. Capture continues -- see spec 0032 Part 3.
	LIFT = "lift"


class SilenceCap:
	"""Tracks one silence window and says, at each instant, what is owed.

	Each of :data:`SilenceCapAction.WARN` and :data:`SilenceCapAction.LIFT` is
	returned AT MOST ONCE PER WINDOW, so a loop polling every few hundred
	milliseconds does not repeat itself. A new window begins when the human hears
	something (:meth:`heard`) or when a lifted session goes quiet again
	(:meth:`resuppressed`).
	"""

	def __init__(self, policy: SilenceCapPolicy, now: float) -> None:
		self._policy = policy
		#: When the human last heard their machine. Seeded at session start, which
		#: is honest: the start cue is itself one of the three sounds that get past
		#: the suppression.
		self._since = now
		self._warned = False
		self._lifted = False
		#: Set while an askUser window holds the suppression open; see paused().
		self._paused_at: float | None = None

	# -- state a caller may read ---------------------------------------------

	@property
	def policy(self) -> SilenceCapPolicy:
		"""The thresholds this cap is holding to."""
		return self._policy

	@property
	def lifted(self) -> bool:
		"""Whether the cap has already un-muted this session."""
		return self._lifted

	@property
	def is_paused(self) -> bool:
		"""Whether the clock is stopped right now (an askUser window is open)."""
		return self._paused_at is not None

	# -- events --------------------------------------------------------------

	def heard(self, now: float) -> None:
		"""The human heard their machine: start a fresh window.

		Called for exactly the sounds that reach the synth past the suppression
		filter. Anything an agent does that produces no sound -- pressing keys,
		typing, reading buffers back -- must NOT come through here, however much of
		it there is.
		"""
		self._since = now
		self._warned = False

	def paused(self, now: float) -> None:
		"""Stop the clock: an askUser window has suspended the suppression.

		The human hears everything for that whole window, so counting silence
		through it would fire the cap at the one moment it is provably not needed.
		Idempotent.
		"""
		if self._paused_at is None:
			self._paused_at = now

	def resumed(self, now: float) -> None:
		"""Restart the clock after a window, without charging it for the wait.

		The window's duration is added to the mark rather than the mark being
		reset, so "the clock does not run" is exactly what happens. Idempotent.
		"""
		if self._paused_at is None:
			return
		self._since += now - self._paused_at
		self._paused_at = None

	def resuppressed(self, now: float) -> None:
		"""A lifted session went quiet again: a fresh window, from zero.

		This is what keeps exposure bounded however many times a session re-arms --
		an agent cannot accumulate unbounded silence out of bounded pieces, because
		every piece is bounded and every boundary is heard.
		"""
		self._lifted = False
		self._warned = False
		self._since = now

	# -- the question the loop asks ------------------------------------------

	def check(self, now: float) -> SilenceCapAction:
		"""What is owed at ``now``. Never raises, and never repeats an act."""
		if not self._policy.enabled or self._lifted or self._paused_at is not None:
			return SilenceCapAction.NONE
		elapsed = now - self._since
		# The LIFT is tested first, deliberately. It is the guarantee; the warning
		# is a courtesy. A loop starved past both thresholds at once must give the
		# human their machine back, not spend the turn warning about a silence that
		# has already run past the limit.
		if elapsed >= self._policy.lift_after:
			self._lifted = True
			self._warned = True
			return SilenceCapAction.LIFT
		if not self._warned and elapsed >= self._policy.warn_after:
			self._warned = True
			return SilenceCapAction.WARN
		return SilenceCapAction.NONE
