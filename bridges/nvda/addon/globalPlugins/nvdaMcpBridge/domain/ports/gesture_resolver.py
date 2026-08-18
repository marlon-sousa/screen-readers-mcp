# nvdaMcpBridge domain -- GestureResolver: what keys the reader is ACTUALLY on.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: domain port. Ask the reader which gestures are bound to the commands
#       that decide a persona's boundary, ON THIS MACHINE, RIGHT NOW.
# IMPLEMENTED BY: adapters/nvda_gesture_resolver.py.
# USED BY: domain/entities/reader_guidance.py, which renders the answer into the
#          document `getGuidance` returns.
#
# WHY THIS EXISTS, and it is the whole point of it. The first version of the
# guidance document hard-coded NVDA's DEFAULT key bindings, transcribed from
# NVDA's own source. That is wrong in a way that is worse than being vague:
#
#   * NVDA lets anyone remap any command, and a remapped gesture DOES NOT FAIL.
#     It quietly does something else. So an agent cannot detect the divergence by
#     listening, and "assume the defaults and complain if they are wrong" asks it
#     to notice something it has no way to see.
#   * The failure lands in the UNSAFE direction. A `user` session would be warned
#     off a key that is now harmless, and told nothing about the key that now IS
#     object navigation -- so the persona whose entire point is a boundary gets
#     the boundary wrong.
#   * Desktop and laptop layouts bind different keys, and a static document has to
#     print both and admit it cannot tell which one you are on. Half of every such
#     table is false on any given machine.
#
# The reader knows all of this exactly. So we ask it, and print what it says.
# There is deliberately NO table of documented defaults to compare against: a
# hand-maintained "the default is X" is the same assumption we are removing, one
# level up, and it would go stale the first time NVDA changed one.

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol, runtime_checkable

#: The command groups a document asks for, named by the DOMAIN so that a bridge
#: for another reader can answer the same questions with its own vocabulary.
#: Each maps to whatever that reader calls the group -- on NVDA, to its own
#: script categories, which is why nothing here is an NVDA constant.
#:
#: The first three are the BOUNDARY: commands that reach a control the keyboard
#: cannot. The fourth is the opposite -- commands that only re-read what is
#: already there, and are therefore inside every persona's vocabulary.
GROUP_OBJECT_NAVIGATION = "object-navigation"
GROUP_TEXT_REVIEW = "text-review"
GROUP_MOUSE = "mouse"
GROUP_READING = "reading"

#: Every group a resolver is expected to answer for, in the order a document
#: presents them.
ALL_GROUPS: tuple[str, ...] = (
	GROUP_READING,
	GROUP_OBJECT_NAVIGATION,
	GROUP_TEXT_REVIEW,
	GROUP_MOUSE,
)


@dataclass(frozen=True)
class ResolvedCommand:
	"""One reader command, and the gestures bound to it on this machine."""

	#: The reader's own description of the command. Localised, because it is the
	#: reader's string -- an agent driving a Portuguese NVDA reads a Portuguese
	#: description, which is honest: that is what the person at the machine sees
	#: in the reader's own input-gestures dialog.
	name: str

	#: The reader's stable, UNTRANSLATED identifier for the command
	#: (``navigatorObject_next``). The identity, as opposed to the description:
	#: it survives a language change and a rebinding, so a finding can name the
	#: command even when the keys have moved.
	script: str

	#: Every gesture bound to it, ready to pass straight to ``pressGesture``.
	#: EMPTY IS A REAL ANSWER -- the command exists and nothing is bound to it,
	#: which a document should say rather than silently omit the row.
	gestures: list[str] = field(default_factory=lambda: [])


@runtime_checkable
class GestureResolver(Protocol):
	"""Reports the live gesture bindings for the groups a persona cares about."""

	def resolve(self) -> dict[str, list[ResolvedCommand]]:
		"""Return the commands in every group of :data:`ALL_GROUPS`.

		A SNAPSHOT, taken when it is called. Readers can rebind per application
		or per configuration profile, so the answer is true of the moment rather
		than of the session -- which the document says out loud instead of
		implying a permanence it cannot offer.

		A group the reader cannot answer for maps to an empty list rather than
		being absent, so a caller never has to distinguish "no such group" from
		"nothing in it".
		"""
		...
