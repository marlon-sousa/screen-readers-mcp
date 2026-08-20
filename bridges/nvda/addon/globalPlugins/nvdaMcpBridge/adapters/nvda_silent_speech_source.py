# nvdaMcpBridge adapters -- NvdaSilentSpeechSource: silent-mode capture + suppress.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the SpeechSource port for SILENT mode. On pyright's
#       ignore list (imports NVDA); validated by the 9c live-NVDA checklist.
# BUILT BY: adapters/nvda_adapter_factory.py when hello asks for silent mode.
# COLLABORATORS: speech.extensions.filter_speechSequence -- a FILTER NVDA applies
#                to every speech sequence inside speak(), BEFORE it reaches the
#                synth (speech/speech.py:1096; if the filter returns an empty
#                sequence, speak() returns and nothing is synthesized).
#
# THE DESIGN (agreed with Marlon, replacing the old spy-synth swap): we do NOT
# touch the synth at all. NVDA's real synth (espeak/ibmeci/...) stays loaded and
# active, so NVDA and every other add-on keep seeing their configured synth as
# valid -- fully transparent. We register a filter that CAPTURES each sequence
# into the buffer and then returns it EMPTIED, so no audio is produced. "Restore"
# is just stop() unregistering the filter -- speech flows again instantly, with no
# synth reload that could fail. And because NVDA holds filter handlers by WEAK
# reference, if this addon ever dies the suppression lifts on its own: the tester
# can never be stranded mute. If our handler raises, NVDA keeps the original
# sequence (extensionPoints.Filter.apply swallows handler errors), so a bug here
# fails safe toward speech, not silence.
#
# NVDA holds the handler weakly, so this instance must outlive the registration --
# the AdapterSet keeps it for the session; stop() unregisters at teardown.
#
# suspend(): unregister the filter temporary, so the tester hears speech during
# an interaction window. resume(): re-register it. Both are idempotent.
# Fails safe: a resume() that never happens leaves speech on, not silence.
#
# THREE STATES, not two (spec 0032, board entry 11.10). The silence cap bounds how
# long a human may be unable to hear their own machine, and its remedy is to stop
# SUPPRESSING without stopping CAPTURING -- which suspend() cannot do, because the
# filter it unregisters is where capture happens. So this adapter carries a second
# flag beside _registered:
#
#   registered  suppressing  words to the synth  words to the buffer
#   yes         yes          no                  YES   (silent mode as shipped)
#   no          --           yes                 no    (an askUser window)
#   yes         NO           YES                 YES   (passing through, new)
#
# Two consequences fall out of that third row, and both are invisible at the call
# site, which is why each is stated where it is enforced:
#
#   * _advance_callbacks must NOT run while passing through. It exists because an
#     EMPTIED sequence would eat NVDA's CallbackCommands; a sequence returned
#     intact still carries them, NVDA clocks them itself, and running them again
#     would double-advance say all -- re-inflicting the 11.13 wound from the other
#     side.
#   * resume() must not re-mute a lifted session. It re-registers the filter, and
#     that is correct in BOTH registered states: what the filter then DOES is
#     decided by _suppressing, which resume() does not touch. So the trap is
#     closed structurally rather than by a check somebody has to remember.
#
# THE CALLBACK PROBLEM (found live 2026-08-18, board entry 11.13). Emptying the
# sequence suppresses the words, but a speech sequence is not only words: NVDA
# puts BaseCallbackCommands in it, and some of NVDA's own machinery is CLOCKED by
# them. Say all is the clearest case -- speech/sayAll.py:292 inserts a
# CallbackCommand at position 0 of every chunk, and its callback is what moves the
# caret and asks for the NEXT chunk. Returning [] deleted that callback along with
# the words, and speech.speak() then bails at `if not speechSequence: return`
# (speech/speech.py:1102) before the speech manager ever sees it. So say all read
# two chunks -- the ones its own MAX_BUFFERED_LINES fallback queues by itself --
# and then waited forever for a lineReached that could not arrive. Not an NVDA
# limit: a wound we inflicted.
#
# WHY WE RUN THEM OURSELVES rather than pass them through. The tempting fix is to
# return the sequence with only the strings removed, letting the manager turn the
# callbacks into IndexCommands and the synth report them back. That makes the fix
# depend on how each synth treats a text-free utterance, and the drivers do not
# agree: espeak, oneCore, RHVoice and ibmeci all report indexes from an AUDIO
# callback (player.feed(..., onDone=...)), so no audio can mean no index --
# NVDA's own manager names oneCore as a synth that "may skip indexes if before
# another index, with no text content in between" (speech/manager.py:676). Only
# sapi5 is safe, because _onEndStream flushes untriggered bookmarks. And NVDA's
# "No speech" driver is the worst of the set: synthDrivers/silence.py records
# item.index into self.lastIndex, which NOTHING in NVDA reads any more, so it
# notifies nobody. Running the callbacks here is the only mechanism that does not
# vary with the tester's synth choice.
#
# Timing changes, and honestly so: a callback means "when speech reaches this
# point", and in a session with no audio there is no such point. Firing it now is
# the truthful reading of a degenerate case, and it makes a silent say all read
# the document as fast as the event queue turns.
#
# QUEUED, never called inline: lineReached calls nextLine calls speak, which lands
# straight back in this filter. Called inline that is unbounded recursion on
# NVDA's main thread; queued, each chunk gets its own turn of the event loop --
# which is also how NVDA itself defers index handling (manager.py:599).

from __future__ import annotations

from collections.abc import Callable
from typing import TYPE_CHECKING, Any

import queueHandler
from logHandler import log
from speech.commands import BaseCallbackCommand, BeepCommand, WaveFileCommand
from speech.extensions import filter_speechSequence

from ..domain.ports.speech_source import SpeechSource

if TYPE_CHECKING:
	from ..domain.entities.speech_buffer import SpeechBuffer

#: Written into NVDA's own log once per silent session (spec 0021), not once
#: per utterance -- a silent run drops speech from the log entirely (the filter
#: empties the sequence before speech.speak's own log.io line), which otherwise
#: reads, in the human's nvda.log, like an NVDA fault rather than our doing.
SUPPRESSED_MARKER = "nvdaMcpBridge: speech suppressed for this session"
RESTORED_MARKER = "nvdaMcpBridge: speech restored for this session"

#: Why a suppression ended, or began again, when the silence cap was the cause
#: (spec 0032). Written BEFORE the balanced pair above, so a human reading their
#: own nvda.log afterwards finds the reason next to the fact -- and still finds
#: every "suppressed" line answered by a "restored" one, on every path.
CAP_LIFTED_MARKER = "nvdaMcpBridge: silence cap reached -- speech is passing through, capture continues"
CAP_RESUPPRESSED_MARKER = "nvdaMcpBridge: speech suppression re-armed after the silence cap lifted it"


class NvdaSilentSpeechSource(SpeechSource):
	"""Captures NVDA speech and suppresses it, leaving the real synth loaded."""

	def __init__(self) -> None:
		self._buffer: SpeechBuffer | None = None
		self._log_position: Callable[[], int] = lambda: 0
		self._registered = False
		#: Whether the SUPPRESSED marker was written and its pair still owed.
		#: Tracked SEPARATELY from _registered, because suspend() clears that flag
		#: for an interaction window -- so a session torn down with a window open
		#: (which teardown deliberately does NOT resume, to leave the tester
		#: audible) would otherwise write "suppressed" and never "restored",
		#: leaving the human's own nvda.log claiming a suppression that had in
		#: fact ended. That unexplained state is the exact thing the markers exist
		#: to prevent, so the pair must balance on every path.
		self._marked = False
		#: Whether the filter EMPTIES what it captures. Separate from _registered
		#: because the silence cap's lift leaves the filter in place and only stops
		#: the muting -- see the table in this file's header.
		self._suppressing = True

	def start(self, buffer: SpeechBuffer, log_position: Callable[[], int]) -> None:
		self._buffer = buffer
		self._log_position = log_position
		filter_speechSequence.register(self._capture_and_suppress)
		self._registered = True
		self._suppressing = True
		self._mark_suppressed()

	def stop(self) -> None:
		if self._registered:
			filter_speechSequence.unregister(self._capture_and_suppress)
			self._registered = False
		self._mark_restored()
		self._buffer = None

	def suspend(self) -> None:
		"""Unregister the filter so the tester hears speech during a window."""
		if self._registered:
			filter_speechSequence.unregister(self._capture_and_suppress)
			self._registered = False

	def resume(self) -> None:
		"""Re-register the filter; idempotent, safe to call at teardown.

		Deliberately does NOT touch _suppressing, which is what stops it re-muting a
		session the silence cap has lifted (spec 0032 Part 3): it restores whichever
		registered state was in force, never suppression unasked.
		"""
		if not self._registered:
			filter_speechSequence.register(self._capture_and_suppress)
			self._registered = True

	def stop_suppressing(self) -> None:
		"""Pass words through to the synth, still capturing them. Idempotent."""
		if not self._suppressing:
			return
		self._suppressing = False
		log.info(CAP_LIFTED_MARKER)
		self._mark_restored()

	def resume_suppressing(self) -> None:
		"""Go quiet again after a lift. Idempotent."""
		if self._suppressing:
			return
		self._suppressing = True
		log.info(CAP_RESUPPRESSED_MARKER)
		self._mark_suppressed()

	def is_suppressing(self) -> bool:
		"""Whether words are being withheld from the human right now.

		Both flags matter: a suspended filter is withholding nothing either, even
		though this session still intends to.
		"""
		return self._registered and self._suppressing

	# -- the balanced log pair ----------------------------------------------

	def _mark_suppressed(self) -> None:
		"""Write the SUPPRESSED marker, at most one unanswered at a time."""
		if self._marked:
			return
		log.info(SUPPRESSED_MARKER)
		self._marked = True

	def _mark_restored(self) -> None:
		"""Answer an outstanding SUPPRESSED marker. Safe to call on any path."""
		if not self._marked:
			return
		log.info(RESTORED_MARKER)
		self._marked = False

	def _capture_and_suppress(self, speechSequence: Any) -> Any:
		# Runs on NVDA's main thread (inside speak()). Capture the words, keep
		# whatever the sequence was CLOCKING alive, then return an empty sequence
		# so speak() stops before the synth.
		buffer = self._buffer
		if buffer is not None and speechSequence:
			buffer.append(speechSequence, self._log_position())
		if not self._suppressing:
			# Passing through (spec 0032): the sequence goes on to the synth with its
			# callbacks intact and NVDA clocks them itself. Running them here as well
			# would double-advance say all.
			return speechSequence
		self._advance_callbacks(speechSequence)
		return []

	def _advance_callbacks(self, speechSequence: Any) -> None:
		"""Queue each callback the emptied sequence would otherwise have eaten.

		Beeps and wave files are callbacks too, and their whole job is to make a
		sound -- running those would break the one promise a silent session makes,
		so they are the deliberate exception.
		"""
		for item in speechSequence or ():
			if isinstance(item, (BeepCommand, WaveFileCommand)):
				continue
			if isinstance(item, BaseCallbackCommand):
				queueHandler.queueFunction(queueHandler.eventQueue, self._run, item)

	def _run(self, command: Any) -> None:
		# NVDA logs and carries on when a speech callback raises (manager.py:704);
		# ours runs on the event queue instead, where an escape would take down
		# something unrelated, so it stops here.
		try:
			command.run()
		except Exception:
			log.exception("nvdaMcpBridge: speech callback failed in silent mode")
