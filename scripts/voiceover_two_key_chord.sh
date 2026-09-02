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
# about any of its 45 toggles, so this reads the state from the preferences it
# writes instead:
#
#     SCRCInvertedTCommanderCaptureEnabled                    (arrow-key Quick Nav)
#     SCRCUserDefaultsIndependentSingleLetterQuickNavEnabled  (single-key Quick Nav)
#
# BOTH, AND THE SECOND ONE COST A CORRECTION. The first version of this script
# watched the arrow-key flag alone, on the reasonable assumption that Left+Right
# toggles one boolean. MEASURED 2026-09-01: it does not. From
# arrow=0 single=1, one chord gave arrow=1 single=1 and the NEXT chord gave
# arrow=0 single=0 -- so the chord took single-key Quick Nav down with it, and a
# probe watching one flag reported "restored" while it had quietly changed a
# setting the maintainer uses. That is exactly the hazard the 2026-08-29 rule is
# about: a probe must assert the hazard is GONE, and it can only assert about
# what it looks at.
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
# IF THE PROBE SAYS "THE CHORD DID NOTHING", RESTART THE READER BEFORE BELIEVING
# IT. Measured 2026-09-02, on this entry's own live run: this script reported the
# chord doing nothing, exit 3, while the SAME chord through the bridge toggled the
# setting minutes later. The Accessibility grant was present both times
# (AXIsProcessTrusted and CGPreflightPostEventAccess both true) and the flag
# reading was working (the reader's own command name moved it 0 -> 1 -> 0 on that
# same instance). The one difference was the VoiceOver INSTANCE: the failing run
# was against a reader that had been restarted repeatedly with its capture voice
# deregistered. After a clean restart this script passes, from here and from the
# bridge alike.
#
# So a reader can go on dispatching AppleScript commands correctly while no longer
# SEEING synthesized key chords -- which reads exactly like "this platform cannot
# do it" and is not. Which of those conditions mattered was NOT isolated; what is
# recorded is that a restart cleared it. Do not conclude anything about VoiceOver
# from a single exit 3.
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
SINGLE="SCRCUserDefaultsIndependentSingleLetterQuickNavEnabled"
# VoiceOver writes the preference a moment after the toggle, not synchronously.
SETTLE=2

say() { printf '%-42s %s\n' "$1" "$2"; }

# The flag as 0 or 1, or the empty string if the key is not there yet -- which is
# an ANSWER on a machine where arrow-key Quick Nav has never been touched, not a
# failure.
read_flag() {
	plutil -p "$PREFS" 2>/dev/null | grep "$FLAG" | sed 's/.*=> //' | tr -d ' '
}

read_single() {
	plutil -p "$PREFS" 2>/dev/null | grep "$SINGLE" | sed 's/.*=> //' | tr -d ' '
}

# Set one toggle by its own COMMAND NAME, which moves exactly that setting --
# unlike the chord, which is what this script exists to characterise.
set_toggle() {
	local command="$1"
	osascript -e "tell application \"VoiceOver\" to tell commander to perform command \"$command\"" \
		>/dev/null 2>&1
	sleep "$SETTLE"
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
START_SINGLE="$(read_single)"
if [[ -z "$START" ]]; then
	echo "the preference '$FLAG' is not present yet on this machine." >&2
	echo "Toggle arrow-key Quick Nav once by hand (or with the reader's own" >&2
	echo "'toggle arrow-key quick nav on or off' command) so it exists, then re-run." >&2
	exit 1
fi

# RESTORED ON EVERY EXIT PATH, including a failure partway: the one setting this
# touches is somebody's own, and a probe that left Quick Nav on would change how
# their arrow keys behave for the rest of the day.
# RESTORED THROUGH THE COMMAND NAMES, NOT BY PRESSING THE CHORD AGAIN. Each
# command moves exactly one setting and says which way it went; the chord moves
# both and is the thing under test. Restoring with the instrument being measured
# is how the first version of this script left single-key Quick Nav off.
restore() {
	local now single
	now="$(read_flag)"
	if [[ "$now" != "$START" ]]; then
		say "restoring" "arrow-key Quick Nav back to $START"
		set_toggle "toggle arrow-key quick nav on or off"
		now="$(read_flag)"
	fi
	single="$(read_single)"
	if [[ -n "$START_SINGLE" && "$single" != "$START_SINGLE" ]]; then
		say "restoring" "single-key Quick Nav back to $START_SINGLE"
		set_toggle "toggle single-key quick nav on or off"
		single="$(read_single)"
	fi
	if [[ "$now" != "$START" || ( -n "$START_SINGLE" && "$single" != "$START_SINGLE" ) ]]; then
		echo "COULD NOT RESTORE. arrow-key is $now (started $START), single-key is" >&2
		echo "$single (started $START_SINGLE). Put them back in VoiceOver Utility or with" >&2
		echo "the reader's own 'toggle arrow-key quick nav on or off' and" >&2
		echo "'toggle single-key quick nav on or off'." >&2
	fi
}
trap restore EXIT

echo "Quick Nav, read from the reader's own preferences"
say "arrow-key at the start" "$START"
say "single-key at the start" "${START_SINGLE:-<not set>}"
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
say "  single-key Quick Nav is" "$(read_single)   <- watched, because the chord moves it too"
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
echo
echo "AND THE CHORD IS NOT A CLEAN TOGGLE OF ONE SETTING: it moves single-key"
echo "Quick Nav as well, which is why the reader's own command names are the"
echo "route a session should take and this chord is only the thing being proved."
