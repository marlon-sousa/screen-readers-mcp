# Unit tests for domain/controllers/commands/get_config.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import pytest
from fakes.adapter_factory import FakeAdapterFactory
from fakes.clock import FakeClock
from support.context import adapters_from, make_context, request

from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.command_handler import CommandError
from nvdaMcpBridge.domain.controllers.commands.get_config import GetConfigHandler


def test_reads_config_key(clock: FakeClock) -> None:
    factory = FakeAdapterFactory()
    factory.config_accessor.seed(["speech", "synth"], "espeak")
    ctx = make_context(clock, adapters=adapters_from(factory))
    result = GetConfigHandler().execute(
        ctx, request("getConfig", keyPath=["speech", "synth"])
    )
    assert isinstance(result, p.ConfigResult)
    assert result.value == "espeak"


def test_bad_key_propagates_as_command_error(clock: FakeClock) -> None:
    factory = FakeAdapterFactory()
    ctx = make_context(clock, adapters=adapters_from(factory))
    with pytest.raises(CommandError):
        GetConfigHandler().execute(
            ctx, request("getConfig", keyPath=["nonexistent"])
        )
