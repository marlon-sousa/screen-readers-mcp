# Architecture check: a command speaks to the human through ONE call, not two.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# Spec 0032 defines the set of things that reset the silence cap as "exactly the
# set of things that get past the suppression" -- and then left each handler to
# remember the second half. It drifted within one entry: spec 0025's inline
# announcement on pressGesture/typeText, and setLogLevel's confirmation, all
# reached the synth through Announcer.announce and told the clock nothing. On
# 2026-08-20 a session narrating every few seconds was warned at 45 s and
# un-muted at 90 s because of it, which is the exact harm the cap exists to
# prevent, produced by the cap itself.
#
# SessionContext.announce_to_human makes the two halves one call. That is a
# property of the SOURCE rather than of any behaviour: a new handler that spoke
# through the port directly would pass every behavioural test in this directory
# while silently re-opening the hole, and nobody would find out until a human sat
# mute again. Hence this check, walking the AST rather than grepping, so an
# aliased or self-held announcer is caught too.

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

#: session_context.py is the funnel itself -- it is the one place that may make
#: the call, because it is the place that notes it afterwards.
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
	# A guard that can only pass is not a guard.
	assert _speaks_past_the_funnel("ctx.announcer.announce('hi')")
	assert _speaks_past_the_funnel("self.announcer.announce(params.announce)")
	# What must still be allowed: the other half of the port, and the funnel call.
	assert not _speaks_past_the_funnel("ctx.announcer.current_synth()")
	assert not _speaks_past_the_funnel("ctx.announce_to_human('hi')")
