# Unit tests for domain/entities/silence_cap.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import pytest
from nvdaMcpBridge.domain.entities.silence_cap import (
	DEFAULT_LIFT_AFTER,
	DEFAULT_WARN_AFTER,
	SilenceCap,
	SilenceCapAction,
	SilenceCapPolicy,
)

CAPPED = SilenceCapPolicy(enabled=True)
TIGHT = SilenceCapPolicy(enabled=True, warn_after=10.0, lift_after=20.0)


def cap(policy: SilenceCapPolicy = TIGHT, *, start: float = 100.0) -> SilenceCap:
	"""A cap opened at a non-zero *start*, so "elapsed" cannot pass for "now"."""
	return SilenceCap(policy, start)


def test_defaults_are_the_shipped_thresholds() -> None:
	policy = SilenceCapPolicy(enabled=True)
	assert (policy.warn_after, policy.lift_after) == (DEFAULT_WARN_AFTER, DEFAULT_LIFT_AFTER)
	assert (DEFAULT_WARN_AFTER, DEFAULT_LIFT_AFTER) == (45.0, 90.0)


@pytest.mark.parametrize(
	("warn", "lift"),
	[
		(90.0, 45.0),
		(45.0, 45.0),  # equal: the warning would never be spoken
		(0.0, 90.0),
		(-1.0, 90.0),
	],
)
def test_an_unordered_pair_is_refused(warn: float, lift: float) -> None:
	with pytest.raises(ValueError, match="0 < warn < lift"):
		SilenceCapPolicy(enabled=True, warn_after=warn, lift_after=lift)


def test_from_settings_falls_back_to_the_defaults_rather_than_raising() -> None:
	# Two settings read independently can each look sane and still cross over.
	policy = SilenceCapPolicy.from_settings(unattended=False, warn_after=120.0, lift_after=30.0)
	assert policy.enabled
	assert (policy.warn_after, policy.lift_after) == (DEFAULT_WARN_AFTER, DEFAULT_LIFT_AFTER)


def test_from_settings_keeps_the_unattended_choice_it_did_understand() -> None:
	policy = SilenceCapPolicy.from_settings(unattended=True, warn_after=-5.0, lift_after=0.0)
	assert not policy.enabled


def test_from_settings_passes_a_sane_pair_through() -> None:
	policy = SilenceCapPolicy.from_settings(unattended=False, warn_after=20.0, lift_after=40.0)
	assert (policy.enabled, policy.warn_after, policy.lift_after) == (True, 20.0, 40.0)


def test_unattended_means_not_enabled() -> None:
	assert not SilenceCapPolicy.from_settings(unattended=True, warn_after=10.0, lift_after=20.0).enabled


def test_nothing_is_owed_before_the_warning_threshold() -> None:
	c = cap()
	assert c.check(109.9) is SilenceCapAction.NONE


def test_the_warning_fires_at_its_threshold_and_only_once() -> None:
	c = cap()
	assert c.check(110.0) is SilenceCapAction.WARN
	assert c.check(111.0) is SilenceCapAction.NONE
	assert c.check(119.9) is SilenceCapAction.NONE


def test_the_lift_fires_at_its_threshold_and_only_once() -> None:
	c = cap()
	assert c.check(110.0) is SilenceCapAction.WARN
	assert c.check(120.0) is SilenceCapAction.LIFT
	assert c.check(200.0) is SilenceCapAction.NONE
	assert c.lifted


def test_a_starved_loop_lifts_rather_than_spending_the_turn_warning() -> None:
	c = cap()
	assert c.check(300.0) is SilenceCapAction.LIFT
	assert c.check(301.0) is SilenceCapAction.NONE


def test_a_lifted_cap_stays_quiet_forever_until_re_suppressed() -> None:
	c = cap()
	c.check(120.0)
	for now in (130.0, 200.0, 1000.0):
		assert c.check(now) is SilenceCapAction.NONE


def test_hearing_something_starts_a_fresh_window() -> None:
	c = cap()
	c.heard(105.0)
	assert c.check(114.9) is SilenceCapAction.NONE
	assert c.check(115.0) is SilenceCapAction.WARN
	assert c.check(125.0) is SilenceCapAction.LIFT


def test_hearing_something_re_arms_a_warning_already_spent() -> None:
	c = cap()
	assert c.check(110.0) is SilenceCapAction.WARN
	c.heard(112.0)
	assert c.check(122.0) is SilenceCapAction.WARN


def test_the_clock_does_not_run_while_a_prompt_is_open() -> None:
	c = cap()
	c.paused(105.0)
	assert c.is_paused
	# The prompt suspended the suppression, so the human was hearing everything.
	assert c.check(225.0) is SilenceCapAction.NONE
	c.resumed(225.0)
	assert not c.is_paused
	assert c.check(229.9) is SilenceCapAction.NONE
	assert c.check(230.0) is SilenceCapAction.WARN
	assert c.check(240.0) is SilenceCapAction.LIFT


def test_pause_and_resume_are_idempotent() -> None:
	c = cap()
	c.paused(105.0)
	c.paused(115.0)
	c.resumed(125.0)
	c.resumed(135.0)
	assert c.check(129.9) is SilenceCapAction.NONE
	assert c.check(130.0) is SilenceCapAction.WARN


def test_re_suppression_opens_a_fresh_bounded_window() -> None:
	c = cap()
	assert c.check(120.0) is SilenceCapAction.LIFT
	c.resuppressed(130.0)
	assert not c.lifted
	assert c.check(139.9) is SilenceCapAction.NONE
	assert c.check(140.0) is SilenceCapAction.WARN
	assert c.check(150.0) is SilenceCapAction.LIFT


def test_silence_cannot_be_accumulated_out_of_bounded_pieces() -> None:
	c = cap()
	now = 100.0
	for _ in range(3):
		now += 20.0
		assert c.check(now) is SilenceCapAction.LIFT
		c.resuppressed(now)


def test_a_disabled_policy_never_asks_for_anything() -> None:
	c = cap(SilenceCapPolicy(enabled=False, warn_after=10.0, lift_after=20.0))
	for now in (110.0, 120.0, 10_000.0):
		assert c.check(now) is SilenceCapAction.NONE
	assert not c.lifted


def test_the_policy_is_readable_back_off_the_cap() -> None:
	c = cap(CAPPED)
	assert c.policy is CAPPED
