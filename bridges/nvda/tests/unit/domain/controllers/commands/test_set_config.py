# Unit tests for domain/controllers/commands/set_config.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import pytest
from fakes.adapter_factory import FakeAdapterFactory
from fakes.clock import FakeClock
from support.context import adapters_from, make_context, request

from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.command_handler import CommandError
from nvdaMcpBridge.domain.controllers.commands.set_config import SetConfigHandler


def test_sets_and_returns_prior_value(clock: FakeClock) -> None:
    factory = FakeAdapterFactory()
    factory.config_accessor.seed(["speech", "synth"], "espeak")
    ctx = make_context(clock, adapters=adapters_from(factory))
    result = SetConfigHandler().execute(
        ctx, request("setConfig", keyPath=["speech", "synth"], value="sapi5")
    )
    assert isinstance(result, p.ConfigResult)
    assert result.value == "espeak"
    assert factory.config_accessor.set_calls == [
        (["speech", "synth"], "sapi5")
    ]


def test_mutates_reader_is_true() -> None:
    assert SetConfigHandler.mutates_reader is True


def test_bad_key_propagates_as_command_error(clock: FakeClock) -> None:
    factory = FakeAdapterFactory()
    ctx = make_context(clock, adapters=adapters_from(factory))
    with pytest.raises(CommandError):
        SetConfigHandler().execute(
            ctx, request("setConfig", keyPath=["nonexistent"], value="x")
        )


def test_first_write_records_prior(clock: FakeClock) -> None:
    factory = FakeAdapterFactory()
    factory.config_accessor.seed(["test"], "original")
    ctx = make_context(clock, adapters=adapters_from(factory))
    SetConfigHandler().execute(
        ctx, request("setConfig", keyPath=["test"], value="first")
    )
    SetConfigHandler().execute(
        ctx, request("setConfig", keyPath=["test"], value="second")
    )
    # The prior value returned by the first write was "original";
    # restore_all brings it back to original, not first.
    factory.config_accessor.restore_all()
    assert factory.config_accessor.get(["test"]) == "original"
