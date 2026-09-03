#!/bin/bash
# The same key, pressed again, is a DIFFERENT command. What resets the count?
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     bash scripts/voiceover_press_count.sh
#
# ROLE: the versioned instrument behind the multi-press section of this reader's
# guidance document. It presses one key several times and reads back what the
# reader said each time. It changes NOTHING: `vo+f7` speaks the time, the battery
# or the wifi status depending on the count, and none of the three moves the
# cursor or touches a setting.
#
# WHY IT EXISTS. VoiceOver binds SEVERAL commands to one key and tells them apart
# by how many times it was pressed -- the reader's own factory configuration
# carries a `pressCount` field, which `scripts/voiceover_default_bindings.py`
# prints as "(pressed 2 times)". Thirty of the 301 default bindings are like this.
# So an agent that presses such a key does not necessarily get the command it
# named, and NOTHING IN THE RESULT SAYS SO: `press_gesture` reports what it
# pressed, and what came back is speech from a different command entirely.
#
# WHAT WAS MEASURED, macOS 15.0, 2026-09-02, on the maintainer's machine, through
# this bridge's own key presser:
#
#   * FOUR PRESSES TWO SECONDS APART CYCLE: wifi, time, battery, wifi. The count
#     keeps advancing across separate presses rather than starting again.
#   * A DIFFERENT KEY RESETS IT. After `vo+f2` (describe window), the next
#     `vo+f7` gave the time and date -- count 1.
#   * WAITING DOES NOT. Ten seconds after a press, the next one gave the battery
#     status -- count 2, still.
#
# So the rule an agent can act on is: **press something else first**, and then the
# key means what its single-press binding says. Time does not help.
#
# AND APPLE'S OWN DOCUMENTATION SAYS SOMETHING SUBTLY DIFFERENT, which is why this
# script exists rather than a citation. The support pages list the multi-press
# form as "VO-Fn-F7-F7" and, for two commands, say "press again to cycle through
# these actions" -- which reads as "press twice in quick succession". Nothing there
# says what resets the count, and the measurement above says it is not time. The
# maintainer's own account of using it is the accurate one: "for me it is a ring,
# every time I press it it reads a different information."
#
# HOW IT IS OBSERVED, AND WHAT THAT COSTS. `content of last phrase` is VoiceOver's
# own record of what it last output, read over AppleScript -- so this script needs
# the AppleScript switch ON, unlike the bridge itself (board entry 13.26). It is a
# measuring instrument rather than a part of the product: what the BRIDGE reads is
# the capture voice, and the same fact is visible there.
#
# THE THREE ANSWERS ARE SELF-IDENTIFYING, which is why this key was chosen for the
# measurement: a time, a battery percentage and a signal strength cannot be
# mistaken for each other, or for the window description used as the control. A
# probe whose answers looked alike is what made an earlier attempt at this
# measurement worthless.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESS="$HERE/voiceover_chord_press.swift"
SETTLE=2

say() { printf '%-34s %s\n' "$1" "$2"; }
phrase() { osascript -e 'tell application "VoiceOver" to return content of last phrase' 2>/dev/null; }
press() { swift "$PRESS" press control option "$1" >/dev/null 2>&1; sleep "$SETTLE"; }

if ! pgrep -x VoiceOver >/dev/null; then
	echo "VoiceOver is not running, so there is nothing to measure." >&2
	exit 1
fi
if [[ -z "$(phrase)" ]]; then
	echo "This script reads the reader's own 'last phrase', which needs the" >&2
	echo "AppleScript switch ON (VoiceOver Utility > General). The bridge does not." >&2
	exit 1
fi

echo "vo+f7 is three commands: the time and date, the battery, the wifi status."
echo

echo "Four presses, two seconds apart:"
for count in 1 2 3 4; do
	press f7
	say "  press $count" "$(phrase)"
done
echo

echo "Does a DIFFERENT key reset the count?"
press f2
say "  after vo+f2 (describe window)" "$(phrase)"
press f7
say "  then vo+f7" "$(phrase)"
echo

echo "Does WAITING reset it?"
sleep 10
press f7
say "  10 seconds later, vo+f7" "$(phrase)"
echo

echo "READ THE THREE ANSWERS, because this script cannot assert on them: the"
echo "reader renders in the machine's own language and a time, a percentage and a"
echo "signal strength are not comparable strings. What was measured on 2026-09-02"
echo "is in the header -- a different key resets the count, and time does not."
