#!/bin/bash
# Does this reader see two ORDINARY keys pressed together?
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     bash scripts/voiceover_two_key_chord.sh
#
# ROLE: the versioned instrument board entry 13.22 rests on -- the measurement
# that decides whether this bridge can learn to press `leftArrow+rightArrow`, run
# before the spec rather than quoted from a session nobody can reproduce (the
# 2026-08-22 rule).
#
# WHY IT EXISTS. An agent driving this bridge could not turn Quick Nav on: a Mac
# user does it by pressing Left Arrow and Right Arrow AT THE SAME TIME, and a
# keystroke here is modifiers plus exactly ONE key. Before generalising the
# notation, one thing had to be known and could not be reasoned out: does
# VoiceOver's chord detection accept SYNTHESIZED simultaneity at all? Spec 0048
# is the reason for asking rather than assuming -- there, setting modifier flags
# looked right and was not, and the events had to be real transitions.
#
# WHAT IT MEASURES, AND WHY THE ANSWER IS READABLE. VoiceOver answers no query
# about any of its 45 toggles, so this reads the state from the preference it
# writes instead:
#
#     SCRCInvertedTCommanderCaptureEnabled   (arrow-key Quick Nav, 0 or 1)
#
# in ~/Library/Group Containers/group.com.apple.VoiceOver/Library/Preferences/
# com.apple.VoiceOver4/default.plist. That key was FOUND rather than recalled, by
# the state-comparison technique in docs/how-we-found-the-voice-store.md: snapshot
# the plist, toggle arrow-key Quick Nav through the reader's own command name,
# snapshot again, and read the diff. Nothing in this repo had named it before.
#
# THE EXPERIMENT IS A CONTROL, A PROBE AND A CONTROL, which is the 2026-08-29
# rule about probes: the two keys are first pressed SEQUENTIALLY -- down and up
# each, one after the other -- and the flag must NOT move. Then they are pressed
# TOGETHER and it must. Then together again, so the flip is causation rather than
# a coincidence, and so the machine ends where it started.
#
# Without the sequential control the probe proves only that two arrow presses do
# something, which is a much weaker claim and the one that would have let a wrong
# design through.
#
# IT NEEDS TWO GRANTS: Accessibility, because it posts real key events, and
# AppleEvents-to-VoiceOver only if you use --restore-with-command. That is the
# same split as `voiceover_chords.sh`, for the same reason.
#
# IT IS SAFE IN THE SPECIFIC SENSE THE OTHER PROBES ARE: it starts nothing,
# restarts nothing, and the ONE setting it touches is the one it is measuring --
# which it puts back on every exit path, including a failure. It presses only the
# two arrow keys, which move a cursor and destroy nothing.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESS="$HERE/voiceover_chord_press.swift"
PREFS="$HOME/Library/Group Containers/group.com.apple.VoiceOver/Library/Preferences/com.apple.VoiceOver4/default.plist"
FLAG="SCRCInvertedTCommanderCaptureEnabled"
# VoiceOver writes the preference a moment after the toggle, not synchronously.
SETTLE=2

say() { printf '%-42s %s\n' "$1" "$2"; }

# The flag as 0 or 1, or the empty string if the key is not there yet -- which is
# an ANSWER on a machine where arrow-key Quick Nav has never been touched, not a
# failure.
read_flag() {
	plutil -p "$PREFS" 2>/dev/null | grep "$FLAG" | sed 's/.*=> //' | tr -d ' '
}

if ! pgrep -x VoiceOver >/dev/null; then
	echo "VoiceOver is not running, so there is nothing to measure." >&2
	echo "Start it with: open -a VoiceOver   (never killall on its own)" >&2
	exit 1
fi
if [[ ! -f "$PRESS" ]]; then
	echo "missing $PRESS" >&2
	exit 1
fi

START="$(read_flag)"
if [[ -z "$START" ]]; then
	echo "the preference '$FLAG' is not present yet on this machine." >&2
	echo "Toggle arrow-key Quick Nav once by hand (or with the reader's own" >&2
	echo "'toggle arrow-key quick nav on or off' command) so it exists, then re-run." >&2
	exit 1
fi

# RESTORED ON EVERY EXIT PATH, including a failure partway: the one setting this
# touches is somebody's own, and a probe that left Quick Nav on would change how
# their arrow keys behave for the rest of the day.
restore() {
	local now
	now="$(read_flag)"
	if [[ "$now" != "$START" ]]; then
		say "restoring" "arrow-key Quick Nav back to $START"
		swift "$PRESS" together leftArrow rightArrow >/dev/null 2>&1
		sleep "$SETTLE"
		now="$(read_flag)"
		if [[ "$now" != "$START" ]]; then
			echo "COULD NOT RESTORE: arrow-key Quick Nav is $now and started at $START." >&2
			echo "Put it back with VoiceOver's own 'toggle arrow-key quick nav on or off'." >&2
		fi
	fi
}
trap restore EXIT

echo "arrow-key Quick Nav, read from the reader's own preference"
say "at the start" "$START"
echo

# -- the control ---------------------------------------------------------------
say "CONTROL: pressing them SEQUENTIALLY" "left, then right, each down and up"
swift "$PRESS" press leftArrow >/dev/null
swift "$PRESS" press rightArrow >/dev/null
sleep "$SETTLE"
AFTER_SEQUENTIAL="$(read_flag)"
say "  the flag is now" "$AFTER_SEQUENTIAL"
if [[ "$AFTER_SEQUENTIAL" != "$START" ]]; then
	echo "  UNEXPECTED: two separate presses moved it. Simultaneity is not what" >&2
	echo "  this reader is detecting, and the whole premise needs re-examining." >&2
	exit 2
fi
say "  as expected" "unchanged -- separate presses are not a chord"
echo

# -- the probe -----------------------------------------------------------------
say "PROBE: pressing them TOGETHER" "both down in order, both up in reverse"
swift "$PRESS" together leftArrow rightArrow >/dev/null
sleep "$SETTLE"
AFTER_TOGETHER="$(read_flag)"
say "  the flag is now" "$AFTER_TOGETHER"
if [[ "$AFTER_TOGETHER" == "$START" ]]; then
	echo "  THE CHORD DID NOTHING. Either this reader does not accept synthesized" >&2
	echo "  simultaneity, or the Accessibility grant is missing -- a key event" >&2
	echo "  posted without it is dropped by the window server with nothing said" >&2
	echo "  anywhere. Check the grant before concluding anything about VoiceOver." >&2
	exit 3
fi
say "  it flipped" "the reader saw two ordinary keys held together"
echo

# -- the control again ---------------------------------------------------------
say "CONTROL: pressing them TOGETHER again" "which must flip it back"
swift "$PRESS" together leftArrow rightArrow >/dev/null
sleep "$SETTLE"
AFTER_SECOND="$(read_flag)"
say "  the flag is now" "$AFTER_SECOND"
if [[ "$AFTER_SECOND" != "$START" ]]; then
	echo "  it did not come back. One flip could be a coincidence; two in opposite" >&2
	echo "  directions could not, and this run did not get the second." >&2
	exit 4
fi
echo
echo "MEASURED: two ordinary keys pressed together ARE a chord to this reader,"
echo "and the same two pressed separately are not. Board entry 13.22, spec 0051."
