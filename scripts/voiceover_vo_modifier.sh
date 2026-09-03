#!/bin/bash
# Does this reader see a synthesized VO chord, and what is VO bound to here?
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     bash scripts/voiceover_vo_modifier.sh
#
# ROLE: the versioned instrument board entry 13.25 rests on -- the measurement
# that decides whether this bridge can learn to press `vo+m`, run BEFORE the spec
# rather than quoted from a session nobody can reproduce (the 2026-08-22 rule).
#
# WHY IT EXISTS. A VoiceOver user reaches the menu bar by pressing VO-M. This
# bridge dispatches the command name `go to menu bar` instead, which is a
# different path through the machine -- it is handled INSIDE the reader and never
# passes the application under test -- so an application that swallows or
# reinterprets the keystroke is invisible to it. Before teaching the notation a
# `vo` modifier, two things had to be known and neither could be reasoned out:
#
#   1. WHAT `vo` RESOLVES TO ON A GIVEN MACHINE. VoiceOver's modifier is
#      Control-Option, or Caps Lock, or either, and the person chooses. This
#      script reads that choice rather than guessing at it.
#   2. WHETHER THE READER SEES A SYNTHESIZED ONE AT ALL. Spec 0048 §2.5 is the
#      reason for asking rather than assuming -- there, setting modifier flags
#      looked right, read well in review, and did not work; the events had to be
#      real transitions. And the 2026-08-30 finding that the reader's own modifier
#      COMMANDS do not compose is a standing warning that this reader's input
#      handling has surprises.
#
# WHERE THE SETTING LIVES, AND HOW THE KEY WAS FOUND. VoiceOver records only
# DEVIATIONS from its defaults, so an ABSENT key is the Control-Option default and
# a present one is the person's own choice -- the same shape
# `VoiceOverPrefsScriptingSetting` already encodes for `SCREnableAppleScript`:
#
#     SCRKeysToUseForVOModifier   SCRVOModifierControlOption
#                                 SCRVOModifierCapsLock
#                                 SCRVOModifierControlOptionOrCapsLock
#
# in ~/Library/Group Containers/group.com.apple.VoiceOver/Library/Preferences/
# com.apple.VoiceOver4/default.plist, and in ~/Library/Preferences/com.apple.VoiceOver4/
# default.plist on systems older than Sequoia, which MOVED the file rather than
# adding a second location. The key and its three values are published nowhere:
# they were extracted from the dyld shared cache on 2026-09-02, because the
# `ScreenReader` framework's binary is not on disk as a file. Apple's own
# documentation names only the three choices, in VoiceOver Utility.
#
# WHAT IT MEASURES, AND WHY THE ANSWER IS READABLE. VoiceOver answers no query
# about any of its 45 toggles, so this reads the state from the preferences it
# writes -- exactly as `voiceover_two_key_chord.sh` does, and the two keys are the
# same two:
#
#     SCRCUserDefaultsIndependentSingleLetterQuickNavEnabled  (single-key Quick Nav)
#     SCRCInvertedTCommanderCaptureEnabled                    (arrow-key Quick Nav)
#
# and the two toggles are bound, in this reader's own factory bindings, to VO-Q
# and VO-Shift-Q. Those bindings were read off the machine with
# `scripts/voiceover_default_bindings.py` rather than recalled.
#
# THE EXPERIMENT IS A CONTROL, A PROBE AND A CONTROL, which is the 2026-08-29 rule
# about probes: `q` is pressed ALONE first and the flag must NOT move -- so a flip
# afterwards is the MODIFIER doing it and not the letter. Then VO-Q, which must
# flip it; then VO-Q again, which must flip it back, so the flip is causation
# rather than coincidence and the machine ends where it started. VO-Shift-Q
# follows, to show that a further modifier composes with the reader's own.
#
# IF THE PROBE SAYS "THE CHORD DID NOTHING", RESTART THE READER BEFORE BELIEVING
# IT. Measured 2026-09-02 on 13.22's live run: a reader that has been restarted
# repeatedly with its capture voice deregistered goes on dispatching AppleScript
# commands correctly while no longer SEEING synthesized key events. That reads
# exactly like "this platform cannot do it" and is not.
#
# IT IS SAFE IN THE SPECIFIC SENSE THE OTHER PROBES ARE: it starts nothing,
# restarts nothing, and the only settings it touches are the two it is measuring,
# which it puts back on every exit path -- preferring the reader's own COMMAND
# NAMES, because those are not the thing under test, and falling back to the
# chord with a READ-BACK when that channel is switched off. See `set_toggle`: the
# fallback exists because on 2026-09-02 the command names silently did nothing on
# a machine whose owner had turned AppleScript control off, and this script then
# reported a clean run over two settings it had left moved.
#
# ONE THING TO CHECK BEFORE RUNNING IT: the letter `q` is pressed on its own, so
# whatever holds keyboard focus receives it. Do not run this with a text field
# focused. The Finder, the desktop, or any window with no editable text is fine,
# and the script prints what is frontmost before it starts.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESS="$HERE/voiceover_chord_press.swift"
PREFS="$HOME/Library/Group Containers/group.com.apple.VoiceOver/Library/Preferences/com.apple.VoiceOver4/default.plist"
LEGACY_PREFS="$HOME/Library/Preferences/com.apple.VoiceOver4/default.plist"
MODIFIER_KEY="SCRKeysToUseForVOModifier"
SINGLE="SCRCUserDefaultsIndependentSingleLetterQuickNavEnabled"
ARROW="SCRCInvertedTCommanderCaptureEnabled"
# VoiceOver writes the preference a moment after the toggle, not synchronously.
SETTLE=2

say() { printf '%-42s %s\n' "$1" "$2"; }

read_key() {
	local file="$1" key="$2"
	plutil -p "$file" 2>/dev/null | grep "\"$key\"" | sed 's/.*=> //' | tr -d ' "'
}

read_single() { read_key "$PREFS" "$SINGLE"; }
read_arrow() { read_key "$PREFS" "$ARROW"; }

# Flip one toggle, PREFERRING the reader's own command name, falling back to the
# chord, and VERIFYING BY READ-BACK either way.
#
#     set_toggle <command name> <preference key> <chord argument...>
#
# THE COMMAND NAME IS THE FIRST CHOICE because it moves exactly that setting and
# is not the thing under test. That is 13.22's lesson: a probe that restores with
# the very instrument it is measuring can leave a setting moved and report
# success.
#
# IT IS NOT ALWAYS AVAILABLE, and that is 13.26's, measured here on 2026-09-02.
# With "Allow VoiceOver to be controlled with AppleScript" switched OFF -- which
# a careful user does, because it lets any process on the machine drive their
# screen reader -- `perform command` fails with -1708 and this function used to
# swallow it, restore nothing, and hand the person their Quick Nav settings
# moved. So the chord is the fallback, and the read-back is what makes that
# honest: the objection to restoring with the instrument under test was that it
# was UNVERIFIED, never that it was a chord.
set_toggle() {
	local command="$1" key="$2"
	shift 2
	local before after
	before="$(read_key "$PREFS" "$key")"
	osascript -e "tell application \"VoiceOver\" to tell commander to perform command \"$command\"" \
		>/dev/null 2>&1
	sleep "$SETTLE"
	after="$(read_key "$PREFS" "$key")"
	if [[ "$after" != "$before" ]]; then
		return 0
	fi
	# Say it out loud. A silent fallback is how the failure above stayed invisible.
	say "  the command name did not move it" "falling back to the chord: $*"
	swift "$PRESS" press "$@" >/dev/null 2>&1
	sleep "$SETTLE"
	after="$(read_key "$PREFS" "$key")"
	[[ "$after" != "$before" ]]
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

# -- what VO is bound to on this machine ---------------------------------------

echo "The VoiceOver modifier, read from the reader's own preferences"
BOUND="$(read_key "$PREFS" "$MODIFIER_KEY")"
LEGACY_BOUND="$(read_key "$LEGACY_PREFS" "$MODIFIER_KEY")"
say "  group container" "${BOUND:-<not recorded>}"
say "  pre-Sequoia location" "${LEGACY_BOUND:-<not recorded>}"
RECORDED="${BOUND:-$LEGACY_BOUND}"
case "$RECORDED" in
	"") say "  so VO resolves to" "control+option  (the default -- nothing recorded)" ;;
	SCRVOModifierControlOption) say "  so VO resolves to" "control+option  (chosen)" ;;
	SCRVOModifierControlOptionOrCapsLock)
		say "  so VO resolves to" "control+option  (either is accepted here)" ;;
	SCRVOModifierCapsLock)
		say "  so VO resolves to" "CAPS LOCK ALONE -- control+option is NOT the modifier"
		echo
		echo "This machine's VoiceOver modifier is Caps Lock, so the chords below would" >&2
		echo "not be VO chords here and the measurement would mean nothing. Nothing was" >&2
		echo "pressed. Set the modifier to Control-Option in VoiceOver Utility >" >&2
		echo "Commands if you want to run this." >&2
		exit 1 ;;
	*) say "  so VO resolves to" "UNKNOWN VALUE '$RECORDED' -- stopping"; exit 1 ;;
esac
say "  frontmost application" "$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || echo '<could not ask>')"
# Which restore route this run will get. Printed rather than discovered halfway.
case "$(read_key "$PREFS" "SCREnableAppleScript")" in
	0) say "  AppleScript control" "OFF -- restores fall back to the chord, verified by read-back" ;;
	1) say "  AppleScript control" "on -- restores go through the reader's own command names" ;;
	*) say "  AppleScript control" "not recorded -- the default is off on recent systems" ;;
esac
echo

# -- the state this measurement reads ------------------------------------------

START_SINGLE="$(read_single)"
START_ARROW="$(read_arrow)"
if [[ -z "$START_SINGLE" || -z "$START_ARROW" ]]; then
	echo "one of the Quick Nav preferences is not present yet on this machine." >&2
	echo "Toggle single-key and arrow-key Quick Nav once each (the reader's own" >&2
	echo "'toggle single-key quick nav on or off' and 'toggle arrow-key quick nav on" >&2
	echo "or off' commands do it) so both exist, then re-run." >&2
	exit 1
fi

echo "Quick Nav, read from the reader's own preferences"
say "  single-key at the start" "$START_SINGLE"
say "  arrow-key at the start" "$START_ARROW"
echo

# RESTORED ON EVERY EXIT PATH, including a failure partway, and restored through
# the COMMAND NAMES rather than by pressing the chord again: each command moves
# exactly one setting and says which way it went, and restoring with the very
# instrument under test is how 13.22's first probe left a setting off.
restore() {
	local single arrow
	single="$(read_single)"
	arrow="$(read_arrow)"
	if [[ "$single" != "$START_SINGLE" ]]; then
		say "restoring" "single-key Quick Nav back to $START_SINGLE"
		set_toggle "toggle single-key quick nav on or off" "$SINGLE" control option q
		single="$(read_single)"
	fi
	if [[ "$arrow" != "$START_ARROW" ]]; then
		say "restoring" "arrow-key Quick Nav back to $START_ARROW"
		set_toggle "toggle arrow-key quick nav on or off" "$ARROW" control option shift q
		arrow="$(read_arrow)"
	fi
	if [[ "$single" != "$START_SINGLE" || "$arrow" != "$START_ARROW" ]]; then
		echo "COULD NOT RESTORE. single-key is $single (started $START_SINGLE), arrow-key" >&2
		echo "is $arrow (started $START_ARROW). Put them back in VoiceOver Utility, or with" >&2
		echo "the reader's own 'toggle single-key quick nav on or off' and" >&2
		echo "'toggle arrow-key quick nav on or off'." >&2
	fi
}
trap restore EXIT

# -- the control ---------------------------------------------------------------

say "CONTROL: pressing q ALONE" "no modifier at all"
swift "$PRESS" press q >/dev/null
sleep "$SETTLE"
AFTER_ALONE="$(read_single)"
say "  single-key Quick Nav is now" "$AFTER_ALONE"
if [[ "$AFTER_ALONE" != "$START_SINGLE" ]]; then
	echo "  UNEXPECTED: the bare letter moved it, so a flip below would not be the" >&2
	echo "  modifier's doing. Single-key Quick Nav may be on and 'q' bound; the" >&2
	echo "  premise of this measurement needs re-examining." >&2
	exit 2
fi
say "  as expected" "unchanged -- the letter alone is not the command"
echo

# -- the probe -----------------------------------------------------------------

say "PROBE: pressing control+option+q" "which is VO-Q on this machine"
swift "$PRESS" press control option q >/dev/null
sleep "$SETTLE"
AFTER_CHORD="$(read_single)"
say "  single-key Quick Nav is now" "$AFTER_CHORD"
if [[ "$AFTER_CHORD" == "$START_SINGLE" ]]; then
	echo "  THE VO CHORD DID NOTHING. Either this reader does not see synthesized" >&2
	echo "  VO chords, or the Accessibility grant is missing -- a key event posted" >&2
	echo "  without it is dropped by the window server with nothing said anywhere --" >&2
	echo "  or this reader instance has stopped seeing key events (see the header:" >&2
	echo "  restart it and run this again before concluding anything)." >&2
	exit 3
fi
say "  it flipped" "the reader saw a synthesized VO chord"
echo

# -- the control again ---------------------------------------------------------

say "CONTROL: pressing control+option+q again" "which must flip it back"
swift "$PRESS" press control option q >/dev/null
sleep "$SETTLE"
AFTER_SECOND="$(read_single)"
say "  single-key Quick Nav is now" "$AFTER_SECOND"
if [[ "$AFTER_SECOND" != "$START_SINGLE" ]]; then
	echo "  it did not come back. One flip could be a coincidence; two in opposite" >&2
	echo "  directions could not, and this run did not get the second." >&2
	exit 4
fi
echo

# -- shift on top of the reader's own modifier, which is a MEASUREMENT OF ITS OWN

# THIS PAIR IS THE SHARPEST THING IN THE SCRIPT, and it was found by this entry
# rather than reasoned out. VO-Shift-Q is the arrow-key toggle and VO-Q is the
# single-key one. Posted the obvious way -- Shift held as a real transition, the
# Shift flag set on the key event -- the chord moves the WRONG setting, because a
# CGEvent built from a keycode carries the UNSHIFTED character and this reader
# matches its bindings on the CHARACTER. The only difference between the two runs
# below is the character the event carries.

say "CONTROL: control+option+shift+q, --raw" "the event carrying 'q'"
swift "$PRESS" press --raw control option shift q >/dev/null
sleep "$SETTLE"
RAW_ARROW="$(read_arrow)"
RAW_SINGLE="$(read_single)"
say "  arrow-key Quick Nav is now" "$RAW_ARROW   <- VO-Shift-Q's setting"
say "  single-key Quick Nav is now" "$RAW_SINGLE   <- VO-Q's setting"
if [[ "$RAW_ARROW" != "$START_ARROW" ]]; then
	echo "  UNEXPECTED: the unstamped chord DID reach the shifted binding, so the" >&2
	echo "  character does not decide it on this system and spec 0052 §2.2 needs" >&2
	echo "  re-measuring before anything is built on it." >&2
	exit 5
fi
if [[ "$RAW_SINGLE" == "$START_SINGLE" ]]; then
	echo "  the unstamped chord did nothing at all, which is neither of the two" >&2
	echo "  outcomes this control distinguishes. Re-run; if it repeats, the" >&2
	echo "  measurement below cannot be interpreted." >&2
	exit 6
fi
say "  as measured" "it moved VO-Q's setting: the Shift never arrived"
# Put VO-Q's setting back before the real probe, so the two are not entangled.
set_toggle "toggle single-key quick nav on or off" "$SINGLE" control option q
echo

say "PROBE: the same chord, stamped" "the event carrying 'Q'"
swift "$PRESS" press control option shift q >/dev/null
sleep "$SETTLE"
AFTER_SHIFT="$(read_arrow)"
say "  arrow-key Quick Nav is now" "$AFTER_SHIFT"
if [[ "$AFTER_SHIFT" == "$START_ARROW" ]]; then
	echo "  THE STAMPED CHORD DID NOT REACH THE SHIFTED BINDING EITHER. Then Shift" >&2
	echo "  does not compose with this reader's own modifier at all, which is a real" >&2
	echo "  limit and the spec has to state it." >&2
	exit 7
fi
say "  it flipped" "the shifted binding, reached by the character it carries"
swift "$PRESS" press control option shift q >/dev/null
sleep "$SETTLE"
say "  and back" "$(read_arrow)"
echo

echo "MEASURED, twice over. This reader acts on a SYNTHESIZED VO chord -- the same"
echo "two modifiers a person holds -- while the bare letter does nothing. And a"
echo "SHIFTED chord reaches the binding a person would reach only if the event"
echo "carries the shifted CHARACTER: flags and real Shift transitions are not"
echo "enough, and the same chord without the character moves a different setting"
echo "and reports success. Board entry 13.25, spec 0052."
