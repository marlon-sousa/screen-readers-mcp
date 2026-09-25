# nvdaMcpBridge adapters -- NvdaGestureResolver: ask NVDA what is bound now.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing GestureResolver from inputCore.manager.getAllGestureMappings(), which
#       includes the user's own remappings.
# BUILT BY: plugin.py.
# USED BY: domain/entities/reader_guidance.py.
# Categories are matched against globalCommands' SCRCAT_* constants, never their English text, so the
# match holds in every NVDA language.

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

_CATEGORIES: dict[str, str] = {
	GROUP_OBJECT_NAVIGATION: globalCommands.SCRCAT_OBJECTNAVIGATION,
	GROUP_TEXT_REVIEW: globalCommands.SCRCAT_TEXTREVIEW,
	GROUP_MOUSE: globalCommands.SCRCAT_MOUSE,
}

_READING_SCRIPTS: tuple[str, ...] = (
	"reportCurrentFocus",
	"title",
	"speakForeground",
	"reportCurrentLine",
	"sayAll",
)


class NvdaGestureResolver(GestureResolver):
	def resolve(self) -> dict[str, list[ResolvedCommand]]:
		return run_on_main(self._resolve, block=True)

	def _resolve(self) -> dict[str, list[ResolvedCommand]]:
		resolved: dict[str, list[ResolvedCommand]] = {group: [] for group in ALL_GROUPS}
		try:
			mappings = inputCore.manager.getAllGestureMappings()
		except Exception:
			# Losing the tables only degrades the document; reader_guidance says "could not be resolved".
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

		resolved[GROUP_READING].sort(key=lambda command: _READING_SCRIPTS.index(command.script))
		return resolved

	@staticmethod
	def _group_for(category: str) -> str | None:
		for group, nvda_category in _CATEGORIES.items():
			if category == nvda_category:
				return group
		return None

	@staticmethod
	def _layout() -> str:
		try:
			return str(config.conf["keyboard"]["keyboardLayout"])
		except Exception:
			# NVDA's own default; raising here would cost the whole document.
			return "desktop"

	@staticmethod
	def _keyboard_gestures(identifiers: list[str], layout: str) -> list[str]:
		"""Touch and braille bindings are dropped, because pressGesture sends keystrokes only."""
		kept: list[str] = []
		for identifier in identifiers:
			source, _, keys = identifier.partition(":")
			if not keys or not source.startswith("kb"):
				continue
			if source != "kb" and source != f"kb({layout})":
				continue
			pressable = press_order(keys)
			if pressable not in kept:
				kept.append(pressable)
		return kept
