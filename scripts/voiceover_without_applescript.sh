#!/bin/bash
# What still works when VoiceOver's AppleScript switch is OFF?
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     bash scripts/voiceover_without_applescript.sh
#
# ROLE: the versioned instrument board entry 13.26 rests on. It presses nothing
# that changes a setting, sends no key that types anything, and changes NO state
# at all except the VoiceOver cursor, which one command moves and which moves
# again the moment anybody touches the machine.
#
# WHY IT EXISTS, AND THE REASON IS NOT CONVENIENCE. "Allow VoiceOver to be
# controlled with AppleScript" lets ANY process on the machine drive the screen
# reader a blind person depends on. Marlon's requirement, 2026-09-02: *"a normal
# user doesn't need it, so either I have a solid reason to let it on or it will be
# disabled."* This bridge therefore has to work with it off -- and what actually
# stops working when it is off had to be MEASURED, because the switch's exact
# reach is not documented anywhere Apple publishes.
#
# THE FOUR QUESTIONS, and the fourth is about code this repository already ships:
#
#   1. Does the KEYSTROKE probe still make the reader speak? `vo+f7` is
#      `speak the time and date` -- the same act rung 5 of the handshake
#      performs, as a key. (Measured 2026-09-02 with the switch ON: it does, and
#      the function-key synthesis is unaffected by the fn-key setting.)
#   2. What does `perform command` DO with the switch off -- which error number?
#      The handshake's diagnosis has to name the switch rather than guess at a
#      dead object model, and it can only do that if the two look different.
#   3. Does `tell application "VoiceOver" to return name` still answer? It is an
#      APPLICATION-level event rather than a scripting-object-model one, so it may
#      -- and `TCCPermissionBroker` reads the Automation grant with exactly that
#      script.
#   4. WHAT DO THE TWO RECORDED LOCATIONS SAY? The switch is recorded in
#      VoiceOver's own preferences (`SCREnableAppleScript`) and as a root-owned
#      marker file, and `VoiceOverPrefsScriptingSetting` treats EITHER ONE saying
#      yes as a yes. If VoiceOver Utility clears the preference and leaves the
#      marker behind, that rule reports `enabled` on a machine where the channel
#      is dead -- which nothing else would ever notice.
#
# HOW TO PUT THE MACHINE IN THE STATE THIS MEASURES. Only a human can: VoiceOver
# Utility > General > "Allow VoiceOver to be controlled with AppleScript". There
# is no API that sets it, and writing VoiceOver's preferences behind the reader's
# back is the manoeuvre that destroyed a stored voice setting once already (spec
# 0047, finding 17). This script READS, it never writes.
#
# IT IS WORTH RUNNING IN BOTH STATES, and prints which one it found, so the two
# runs can be compared rather than remembered.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESS="$HERE/voiceover_chord_press.swift"
PREFS="$HOME/Library/Group Containers/group.com.apple.VoiceOver/Library/Preferences/com.apple.VoiceOver4/default.plist"
MARKER="/private/var/db/Accessibility/.VoiceOverAppleScriptEnabled"
PROBE="speak the time and date"

say() { printf '%-46s %s\n' "$1" "$2"; }

if ! pgrep -x VoiceOver >/dev/null; then
	echo "VoiceOver is not running, so there is nothing to measure." >&2
	echo "Start it with: open -a VoiceOver   (never killall on its own)" >&2
	exit 1
fi

# -- 4: what the machine RECORDS ----------------------------------------------

echo "How this machine records the AppleScript switch"
RECORDED="$(plutil -p "$PREFS" 2>/dev/null | grep '"SCREnableAppleScript"' | sed 's/.*=> //' | tr -d ' ')"
say "  SCREnableAppleScript in the preferences" "${RECORDED:-<not recorded — which means OFF>}"
if [[ -e "$MARKER" ]]; then
	say "  the legacy marker file" "PRESENT — $MARKER"
else
	say "  the legacy marker file" "absent"
fi
say "  what this bridge would report" "$(
	if [[ -e "$MARKER" || "$RECORDED" == "1" ]]; then echo "enabled"; else echo "disabled"; fi
)"
echo

# -- 3: the application-level event -------------------------------------------

echo "The two AppleEvent channels, asked separately"
NAME_OUT="$(osascript -e 'tell application "VoiceOver" to return name' 2>&1)"
NAME_CODE=$?
say "  application-level (return name)" "exit $NAME_CODE — $NAME_OUT"

# -- 2: the scripting object model --------------------------------------------

COMMAND_OUT="$(osascript -e "tell application \"VoiceOver\" to tell commander to perform command \"$PROBE\"" 2>&1)"
COMMAND_CODE=$?
say "  the commander (perform command)" "exit $COMMAND_CODE — ${COMMAND_OUT:-<no output, which is success>}"
echo

# -- 1: the keystroke probe ----------------------------------------------------

# READ THROUGH THE READER'S OWN `last phrase` WHERE THAT WORKS, and say so where
# it does not: with the switch off there is no way to read what the reader said
# from a shell at all, which is itself the finding -- it is what the CAPTURE
# VOICE exists for, and what the bridge's rung 5 measures. Here, a human hears it.
echo "The keystroke probe: vo+f7, which is \"$PROBE\""
BEFORE="$(osascript -e 'tell application "VoiceOver" to return content of last phrase' 2>/dev/null)"
say "  what the reader last said" "${BEFORE:-<could not read it — the switch is off>}"
swift "$PRESS" press control option f3 >/dev/null 2>&1
sleep 2
AFTER="$(osascript -e 'tell application "VoiceOver" to return content of last phrase' 2>/dev/null)"
say "  and after the keypress" "${AFTER:-<could not read it — the switch is off>}"
echo

if [[ -n "$AFTER" && "$AFTER" != "$BEFORE" ]]; then
	echo "MEASURED, AND MIND WHAT IT DOES AND DOES NOT SHOW. The reader's own record"
	echo "of what it last output CHANGED, so the reader acted on a synthesized VO"
	echo "chord and produced speech. It does NOT show that the utterance reached"
	echo "this bridge: capture goes through the capture VOICE, which is a different"
	echo "path and is what rung 5 of the handshake requires. Only a session can"
	echo "prove that, which is why the live checklist and not this script is where"
	echo "the two-route probe is signed off."
elif [[ -z "$AFTER" ]]; then
	echo "The reader's own 'last phrase' cannot be read on this machine, which is"
	echo "expected with the switch off. WHETHER THE PROBE SPOKE has to be heard by"
	echo "the person at the machine, or read through the bridge's capture voice —"
	echo "which is exactly what rung 5 of the handshake does and why it is the"
	echo "route board entry 13.26 chooses."
else
	echo "THE KEYSTROKE PROBE SAID NOTHING NEW. Either the Accessibility grant is"
	echo "missing — a key event posted without it is dropped by the window server"
	echo "with nothing said anywhere — or this reader instance has stopped seeing"
	echo "synthesized events (see scripts/voiceover_vo_modifier.sh's header)."
fi
