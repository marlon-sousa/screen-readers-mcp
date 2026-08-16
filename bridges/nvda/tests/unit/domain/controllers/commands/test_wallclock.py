# Unit tests for domain/controllers/commands/wallclock.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# One pure function, so this is the cheapest possible test tier -- but it is the
# single definition of the only time format this protocol has (spec 0028), so it
# is worth pinning: getLogPosition's `time` and every entry's `emittedAt` come
# out of here, and the point of extracting it was that those two cannot drift.

from __future__ import annotations

from datetime import datetime

from nvdaMcpBridge.domain.controllers.commands.wallclock import format_wallclock


def test_renders_the_shape_the_transcript_and_nvdas_own_log_use() -> None:
	# Built from a local datetime rather than a hardcoded epoch, so this asserts
	# the FORMAT without also asserting the machine's timezone.
	moment = datetime(2026, 8, 16, 9, 4, 24, 78_000)
	assert format_wallclock(moment.timestamp()) == "2026-08-16 09:04:24.078"


def test_truncates_to_milliseconds_rather_than_rounding() -> None:
	# %f gives six digits; the last three are noise at the resolution anything
	# here is measured to. Truncation, not rounding -- 999 microseconds past the
	# millisecond must not become the next millisecond.
	moment = datetime(2026, 8, 16, 9, 4, 24, 78_999)
	assert format_wallclock(moment.timestamp()) == "2026-08-16 09:04:24.078"


def test_zero_is_the_empty_string_and_not_nineteen_seventy() -> None:
	# Zero is the buffers' sentinel and the answer for an out-of-range index. It
	# means "no instant was recorded", which an empty string says plainly and a
	# 1970 date actively lies about -- an agent diffing two stamps would compute
	# a fifty-year interval from it.
	assert format_wallclock(0.0) == ""
