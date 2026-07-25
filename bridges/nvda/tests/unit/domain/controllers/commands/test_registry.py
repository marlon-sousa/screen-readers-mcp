# Unit tests for domain/controllers/commands/registry.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# The registry is the one place that must agree with the wire contract: every
# v1 command needs a handler, and the two dispatch policies (available before
# hello, resets inactivity) must be declared on exactly the right handlers.

from __future__ import annotations

from fakes.adapter_factory import FakeAdapterFactory

from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.registry import NVDA_CAPABILITIES, build_command_registry


def test_announced_capabilities_match_what_the_bridge_serves() -> None:
    # All seven capability groups are now served with real ports and NVDA
    # adapters (entry 11.1). The enum defines eight; the bridge serves them all.
    assert NVDA_CAPABILITIES == (
        p.Capability.SPEECH,
        p.Capability.BRAILLE,
        p.Capability.GESTURES,
        p.Capability.FOCUS,
        p.Capability.STATE,
        p.Capability.CONFIG,
        p.Capability.ANNOUNCE,
        p.Capability.TYPING,
    )
    assert len(NVDA_CAPABILITIES) == 8


def test_every_wire_command_has_a_handler() -> None:
    registry = build_command_registry(FakeAdapterFactory(), "x")
    for command in p.Command:
        assert command in registry, f"{command} has no handler"


def test_only_hello_is_available_before_hello() -> None:
    registry = build_command_registry(FakeAdapterFactory(), "x")
    before = {cmd for cmd, handler in registry.items() if handler.available_before_hello}
    assert before == {p.Command.HELLO}


def test_only_ping_skips_the_inactivity_reset() -> None:
    registry = build_command_registry(FakeAdapterFactory(), "x")
    non_resetting = {cmd for cmd, handler in registry.items() if not handler.resets_inactivity}
    assert non_resetting == {p.Command.PING}


def test_set_config_is_the_only_new_mutating_handler() -> None:
    registry = build_command_registry(FakeAdapterFactory(), "x")
    mutating = {cmd for cmd, handler in registry.items() if handler.mutates_reader}
    assert mutating == {p.Command.TYPE_TEXT, p.Command.SET_CONFIG}
