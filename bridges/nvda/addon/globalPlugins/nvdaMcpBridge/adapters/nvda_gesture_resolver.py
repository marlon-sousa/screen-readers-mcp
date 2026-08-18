# nvdaMcpBridge adapters -- NvdaGestureResolver: ask NVDA what is bound now.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the GestureResolver port. On pyright's ignore list
#       (imports NVDA); validated by the 11.20 live-NVDA checklist.
# BUILT BY: plugin.py, at the edge, like the announcer and the log capture.
# USED BY: domain/entities/reader_guidance.py, through the port.
#
# It asks the same question NVDA's own Input Gestures dialog asks --
# ``inputCore.manager.getAllGestureMappings()`` -- which is exactly right: what
# the document should tell an agent is what the dialog would show the person at
# the machine. That call folds in ``manager.userGestureMap`` FIRST, so a
# remapping made by the user is what comes back, not the shipped default.
#
# THREE THINGS THIS FILE GETS RIGHT THAT A HAND-WRITTEN TABLE CANNOT:
#
#   * CATEGORIES, NOT A SCRIPT LIST. The boundary is "everything NVDA itself
#     classifies as object navigation, text review or mouse", taken from
#     globalCommands' own SCRCAT_* constants. So it is self-maintaining: a
#     command NVDA adds to one of those categories appears in the document with
#     no change here, and there is no list of script names to go stale.
#   * LOCALE-PROOF. Those constants are ``_()`` strings evaluated in NVDA's
#     language, and ``scriptInfo.category`` holds the same object -- so comparing
#     the CONSTANT (never the English text) works in every language.
#   * THE LAYOUT IS RESOLVED, NOT GUESSED. ``_gestureMap`` holds both
#     ``kb(desktop):`` and ``kb(laptop):`` identifiers; NVDA picks between them at
#     lookup time. Here they are filtered against the configured layout, so the
#     document prints the keys that will actually work rather than both columns
#     and an apology.
#
# The identifiers come back NORMALIZED -- lower-cased, parts sorted
# (``kb(desktop):nvda+numpad6``). That is unlovely and it is deliberate: it is
# what NVDA has literally bound, and ``bare_key_name`` plus
# ``KeyboardInputGesture.fromName`` accept it verbatim (fromName lower-cases
# every token it resolves), so an agent can paste a cell of the table straight
# into pressGesture.

from __future__ import annotations

import config
import globalCommands
import inputCore
from logHandler import log

from ..domain.ports.gesture_resolver import (
	ALL_GROUPS,
	GROUP_MOUSE,
	GROUP_OBJECT_NAVIGATION,
	GROUP_READING,
	GROUP_TEXT_REVIEW,
	GestureResolver,
	ResolvedCommand,
)
from .keyboard_gesture_name import press_order
from .nvda_main_thread import run_on_main

#: The domain's group names, mapped to NVDA's own script categories. The VALUES
#: are the live constants, not their English text -- see the header.
_CATEGORIES: dict[str, str] = {
	GROUP_OBJECT_NAVIGATION: globalCommands.SCRCAT_OBJECTNAVIGATION,
	GROUP_TEXT_REVIEW: globalCommands.SCRCAT_TEXTREVIEW,
	GROUP_MOUSE: globalCommands.SCRCAT_MOUSE,
}

#: The reading group is the one that is NOT a category, and it is curated on
#: purpose. NVDA's "System caret", "System focus" and "System status" categories
#: hold dozens of commands, most of which an agent will never need; what a
#: persona is told to reach for is a short, deliberate list -- report the focus,
#: the title, the window, the line, and say-all.
#:
#: These are SCRIPT NAMES, which are stable identities rather than key bindings,
#: and a name NVDA retires simply stops appearing rather than becoming a lie.
_READING_SCRIPTS: tuple[str, ...] = (
	"reportCurrentFocus",
	"title",
	"speakForeground",
	"reportCurrentLine",
	"sayAll",
)


class NvdaGestureResolver(GestureResolver):
	"""Reads NVDA's live gesture map on its main thread."""

	def resolve(self) -> dict[str, list[ResolvedCommand]]:
		return run_on_main(self._resolve, block=True)

	def _resolve(self) -> dict[str, list[ResolvedCommand]]:
		resolved: dict[str, list[ResolvedCommand]] = {group: [] for group in ALL_GROUPS}
		try:
			mappings = inputCore.manager.getAllGestureMappings()
		except Exception:
			# A document with no tables is far better than no document: the prose
			# says what each stance may and may not do, and the tables say which
			# keys those are. Losing the second is a degradation, not a failure,
			# and reader_guidance renders "could not be resolved" in their place.
			log.exception("nvdaMcpBridge: could not read NVDA's gesture mappings")
			return resolved

		layout = self._layout()
		for category, commands in mappings.items():
			group = self._group_for(category)
			for info in commands.values():
				if group is None and info.scriptName not in _READING_SCRIPTS:
					continue
				target = group or GROUP_READING
				resolved[target].append(
					ResolvedCommand(
						name=info.displayName,
						script=info.scriptName,
						gestures=self._keyboard_gestures(info.gestures, layout),
					)
				)

		# The reading list is CURATED, so it is put back into the order this
		# bridge's document argues them in -- report where you are, then what
		# window, then read more of it -- rather than whatever order NVDA's
		# categories happened to yield.
		resolved[GROUP_READING].sort(key=lambda command: _READING_SCRIPTS.index(command.script))
		return resolved

	@staticmethod
	def _group_for(category: str) -> str | None:
		"""The domain group for one of NVDA's script categories, or None."""
		for group, nvda_category in _CATEGORIES.items():
			if category == nvda_category:
				return group
		return None

	@staticmethod
	def _layout() -> str:
		"""The keyboard layout in force, which decides which bindings apply."""
		try:
			return str(config.conf["keyboard"]["keyboardLayout"])
		except Exception:
			# NVDA's own default. Being wrong here costs a few rows in a table;
			# raising would cost the whole document.
			return "desktop"

	@staticmethod
	def _keyboard_gestures(identifiers: list[str], layout: str) -> list[str]:
		"""Keep the KEYBOARD gestures that apply on this layout, prefix stripped.

		Touch and braille bindings are dropped rather than shown: this bridge's
		``pressGesture`` sends keystrokes, so a touch gesture in the table would
		be something the agent is told about and cannot perform.
		"""
		kept: list[str] = []
		for identifier in identifiers:
			source, _, keys = identifier.partition(":")
			if not keys or not source.startswith("kb"):
				continue
			# "kb" applies to every layout; "kb(desktop)" only to that one.
			if source != "kb" and source != f"kb({layout})":
				continue
			# THROUGH press_order, and this is load-bearing rather than tidy:
			# NVDA stores its identifiers alphabetically sorted, and fromName
			# reads the LAST token as the key -- so an unreordered `b+nvda`
			# would be handed to an agent as the way to read the window and
			# would instead press NVDA with B held. See keyboard_gesture_name.
			pressable = press_order(keys)
			if pressable not in kept:
				kept.append(pressable)
		return kept
