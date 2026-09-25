# Architecture check: a command speaks to the human through one call, not two.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# SessionContext.announce_to_human speaks and resets the silence cap in one call. A handler that
# spoke through the port directly would pass every behavioural test while the cap missed the sound,
# so this walks the AST to catch aliased or self-held announcers too.

from __future__ import annotations

import ast
from pathlib import Path

import pytest

COMMANDS = (
	Path(__file__).resolve().parents[5]
	/ "addon"
	/ "globalPlugins"
	/ "nvdaMcpBridge"
	/ "domain"
	/ "controllers"
	/ "commands"
)

#: session_context.py is the funnel itself, the one place that may make the call.
HANDLERS = sorted(p.name for p in COMMANDS.glob("*.py") if p.name != "session_context.py")


def _speaks_past_the_funnel(source: str) -> bool:
	"""Whether the file calls ``<anything>.announcer.announce(...)`` itself."""
	for node in ast.walk(ast.parse(source)):
		if not isinstance(node, ast.Call):
			continue
		func = node.func
		if (
			isinstance(func, ast.Attribute)
			and func.attr == "announce"
			and isinstance(func.value, ast.Attribute)
			and func.value.attr == "announcer"
		):
			return True
	return False


@pytest.mark.parametrize("filename", HANDLERS)
def test_a_handler_never_speaks_through_the_announcer_directly(filename: str) -> None:
	source = (COMMANDS / filename).read_text(encoding="utf-8")
	assert not _speaks_past_the_funnel(source), (
		f"{filename} calls announcer.announce directly; use ctx.announce_to_human, "
		"or the human hears it and the silence cap does not (spec 0032)"
	)


def test_the_check_would_actually_fail_on_a_violation() -> None:
	assert _speaks_past_the_funnel("ctx.announcer.announce('hi')")
	assert _speaks_past_the_funnel("self.announcer.announce(params.announce)")
	assert not _speaks_past_the_funnel("ctx.announcer.current_synth()")
	assert not _speaks_past_the_funnel("ctx.announce_to_human('hi')")
