# nvdaMcpBridge domain -- the Announcer port: the bridge's line to the real synth.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: domain port. Direct access to the reader's REAL synth, which stays loaded
#       and active in every mode (silent mode suppresses NVDA's speech at the
#       speak() filter, NOT by swapping the synth -- see nvda_silent_speech_source).
#       So the bridge can always: read the synth's name (for the hello result) and
#       speak a hint through it "regardless" of the suppression (the `announce`
#       command's bridge->human channel).
# USED BY: the hello handler (current_synth) and the AnnounceHandler (announce).
# IMPLEMENTED BY: adapters/nvda_announcer.py (speaks straight through
#                 synthDriverHandler.getSynth(), which bypasses the speak()
#                 suppression filter); tests/fakes/announcer.py FakeAnnouncer.
#
# TRANSPARENCY invariant (agreed with Marlon): NVDA and every add-on must keep
# believing their configured synth is the valid, active one -- it IS. Nothing
# here swaps or terminates it; announce() drives that same live synth directly.

from __future__ import annotations

import enum
from abc import ABC, abstractmethod


class SilenceNotice(enum.Enum):
	"""What the silence cap has to tell the human (spec 0032).

	A closed set rather than a string, because the WORDS are the adapter's
	business: the domain knows what happened, and the reader's own locale decides
	how to say it. This port's own signalling type, so it lives in this file.
	"""

	#: The cap's warning: nothing has been said to you for a while.
	WARNING = "warning"
	#: Suppression has ended. The session is still running and still capturing.
	LIFTED = "lifted"
	#: A lifted session has gone quiet again, on a fresh bounded window.
	RESUPPRESSED = "resuppressed"


class Announcer(ABC):
	"""Reads the reader's real synth and speaks hints through it, in any mode."""

	@abstractmethod
	def current_synth(self) -> str:
		"""Name of the reader's currently configured synth (for ``hello``)."""

	@abstractmethod
	def announce(self, text: str) -> None:
		"""Speak ``text`` aloud to the tester through the real synth.

		Bypasses silent-mode suppression (which lives in NVDA's ``speak()``, not
		in the synth), so a hint is heard even while captured speech is muted.
		"""

	@abstractmethod
	def silence_notice(self, notice: SilenceNotice) -> None:
		"""Tell the human what the SILENCE CAP just did (spec 0032).

		Separate from :meth:`announce` because it must not sound like one. An
		announce is the agent talking; this is the bridge talking ABOUT the agent's
		silence, and the human has to be able to tell them apart before any word
		arrives -- which is the same reasoning that gave announce and askUser
		different cue pitches in the first place.

		Takes an enum and not a string: what happened is the domain's to know, and
		how to say it is the adapter's, in the reader's own language.
		"""
