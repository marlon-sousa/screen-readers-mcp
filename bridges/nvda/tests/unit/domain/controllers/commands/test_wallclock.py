# Unit tests for domain/controllers/commands/wallclock.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from datetime import datetime

from nvdaMcpBridge.domain.controllers.commands.wallclock import format_wallclock


def test_renders_the_shape_the_transcript_and_nvdas_own_log_use() -> None:
	# Built from a local datetime, so this does not also assert the machine's timezone.
	moment = datetime(2026, 8, 16, 9, 4, 24, 78_000)
	assert format_wallclock(moment.timestamp()) == "2026-08-16 09:04:24.078"


def test_truncates_to_milliseconds_rather_than_rounding() -> None:
	moment = datetime(2026, 8, 16, 9, 4, 24, 78_999)
	assert format_wallclock(moment.timestamp()) == "2026-08-16 09:04:24.078"


def test_zero_is_the_empty_string_and_not_nineteen_seventy() -> None:
	# Zero is the buffers' sentinel for "no instant was recorded".
	assert format_wallclock(0.0) == ""
