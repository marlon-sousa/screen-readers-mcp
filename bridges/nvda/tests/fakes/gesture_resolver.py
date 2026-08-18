# nvdaMcpBridge tests -- FakeGestureResolver: the GestureResolver double.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: test double. MIRRORS domain/ports/gesture_resolver.py.
# USED BY: the get_guidance handler tests, and every builder that assembles a
#          SessionContext.
#
# The DEFAULT bindings here are deliberately NOT NVDA's real ones. A fake that
# answered "nvda+numpad6" would let an assertion pass against a document that had
# hard-coded the same string and never asked the reader at all -- which is the
# exact bug this port was built to remove. These are obviously synthetic, so a
# test that finds them in the document has proved the value travelled.

from __future__ import annotations

from nvdaMcpBridge.domain.ports.gesture_resolver import (
	ALL_GROUPS,
	GROUP_MOUSE,
	GROUP_OBJECT_NAVIGATION,
	GROUP_READING,
	GROUP_TEXT_REVIEW,
	GestureResolver,
	ResolvedCommand,
)


def _default_groups() -> dict[str, list[ResolvedCommand]]:
	return {
		GROUP_READING: [
			ResolvedCommand(
				name="Report the focused object",
				script="reportCurrentFocus",
				gestures=["fake+focus"],
			),
			ResolvedCommand(name="Report the window title", script="title", gestures=["fake+title"]),
		],
		GROUP_OBJECT_NAVIGATION: [
			ResolvedCommand(
				name="Move to the next object",
				script="navigatorObject_next",
				gestures=["fake+next"],
			),
			# One command with NOTHING bound, because that is a real state a
			# machine can be in and the document has to render it.
			ResolvedCommand(
				name="Toggle simple review mode",
				script="toggleSimpleReviewMode",
				gestures=[],
			),
		],
		GROUP_TEXT_REVIEW: [
			ResolvedCommand(
				name="Review the current line",
				script="review_currentLine",
				gestures=["fake+review"],
			),
		],
		GROUP_MOUSE: [
			ResolvedCommand(name="Left mouse click", script="leftMouseClick", gestures=["fake+click"]),
		],
	}


class FakeGestureResolver(GestureResolver):
	"""Answers with scripted bindings and counts the asking."""

	def __init__(self, groups: dict[str, list[ResolvedCommand]] | None = None) -> None:
		self.groups = _default_groups() if groups is None else groups
		#: How many times the document asked. The entity must ask ONCE per
		#: document however many markers it holds, or two markers could straddle
		#: a configuration change and print inconsistent halves of one page.
		self.calls = 0

	def resolve(self) -> dict[str, list[ResolvedCommand]]:
		self.calls += 1
		return {group: list(self.groups.get(group, [])) for group in ALL_GROUPS}


class EmptyGestureResolver(GestureResolver):
	"""A reader that could not be asked -- every group comes back empty."""

	def resolve(self) -> dict[str, list[ResolvedCommand]]:
		return {group: [] for group in ALL_GROUPS}
