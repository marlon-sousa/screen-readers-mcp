# Unit tests for adapters/json_lines_channel.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from typing import Any

import pytest
from fakes.script import CLOSED_EVENT, TIMEOUT_EVENT
from fakes.transport import FakeTransport
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.adapters.json_lines_channel import JsonLinesChannel
from nvdaMcpBridge.domain.ports.message_channel import TIMEOUT, ChannelClosed


def _channel(*events: Any) -> tuple[JsonLinesChannel, FakeTransport]:
	transport = FakeTransport(list(events))
	return JsonLinesChannel(transport), transport


def test_reads_a_whole_message() -> None:
	channel, _ = _channel(p.encode_message({"id": 1, "cmd": "ping"}))
	assert channel.read_message() == {"id": 1, "cmd": "ping"}


def test_reassembles_a_message_split_across_chunks() -> None:
	line = p.encode_message({"id": 7, "cmd": "ping"})
	channel, _ = _channel(line[:4], line[4:])
	assert channel.read_message() == {"id": 7, "cmd": "ping"}


def test_two_messages_in_one_chunk_are_delivered_separately() -> None:
	blob = p.encode_message({"id": 1, "cmd": "ping"}) + p.encode_message({"id": 2, "cmd": "bye"})
	channel, _ = _channel(blob)
	assert channel.read_message() == {"id": 1, "cmd": "ping"}
	assert channel.read_message() == {"id": 2, "cmd": "bye"}


def test_a_buffered_message_is_not_lost_to_a_later_timeout() -> None:
	blob = p.encode_message({"id": 1, "cmd": "ping"}) + p.encode_message({"id": 2, "cmd": "bye"})
	channel, _ = _channel(blob, TIMEOUT_EVENT)
	assert channel.read_message() == {"id": 1, "cmd": "ping"}
	assert channel.read_message() == {"id": 2, "cmd": "bye"}
	assert channel.read_message() is TIMEOUT


def test_timeout_is_reported_as_the_sentinel() -> None:
	channel, _ = _channel(TIMEOUT_EVENT)
	assert channel.read_message() is TIMEOUT


def test_reading_on_after_a_timeout_still_works() -> None:
	channel, _ = _channel(TIMEOUT_EVENT, p.encode_message({"id": 3, "cmd": "ping"}))
	assert channel.read_message() is TIMEOUT
	assert channel.read_message() == {"id": 3, "cmd": "ping"}


def test_eof_raises_channel_closed() -> None:
	channel, _ = _channel(CLOSED_EVENT)
	with pytest.raises(ChannelClosed):
		channel.read_message()


def test_unreadable_line_raises_validation_error() -> None:
	channel, _ = _channel(b"not json\n")
	with pytest.raises(p.ValidationError):
		channel.read_message()


def test_write_encodes_a_dataclass_as_one_line() -> None:
	channel, transport = _channel()
	channel.write(p.Response(id=3, result=p.AckResult()))
	assert transport.responses() == [{"id": 3, "result": {"ok": True}, "error": None}]
	assert bytes(transport.outbox).endswith(b"\n")


def test_close_closes_the_transport() -> None:
	channel, transport = _channel()
	channel.close()
	assert transport.closed is True
