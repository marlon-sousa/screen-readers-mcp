#!/bin/bash
# Which of VoiceOver's AppleScript channels are alive on this machine?
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     bash scripts/voiceover_channels.sh
#
# ROLE: the re-runnable instrument behind spec 0047's finding 4 -- and, since
# 2026-08-30, the instrument that CLOSED it. That finding said `perform command`
# fails with error 4 for EVERY command while every read channel answers normally,
# and it stood as a risk to board entry 13.7, which puts the whole gesture
# capability on `perform command`.
#
# IT WAS THE TARGET OBJECT, NOT THE MACHINE. `bridges/voiceover/VoiceOver.sdef`
# says the `application` class responds to `output`, `open`, `close menu` and
# `quit` -- and NOT to `perform command`. The `commander object` responds to it,
# reached through the application's read-only `commander` property. Sending a
# command to an object that does not handle it fails BEFORE any name lookup,
# which is exactly why a valid name and a bogus one both returned 4. Spec 0041
# measured `6` and spec 0047 measured `4` for what looked like the same call
# because their scripts differed, not because the machine changed.
#
# SO THIS SCRIPT NOW PROBES BOTH, and keeps the application probe as a LABELLED
# CONTROL rather than deleting it. The distinction cost two specs an argument and
# an entry a "measured risk"; leaving it visible in the instrument is what stops
# it being rediscovered. A risk nobody can re-measure is a risk nobody can close,
# which is the 2026-08-22 fixture rule applied to a reader instead of a web page.
#
# IT IS SAFE, AND SAFE MEANS SOMETHING SPECIFIC HERE. It does not restart
# VoiceOver, does not write a preference, and does not change a setting. It DOES
# make VoiceOver speak: `output` and `describe item` are the things being tested,
# and a channel cannot be tested without using it. Nothing it does needs undoing.
#
# THE FRONTMOST APPLICATION IS PART OF THE MEASUREMENT, not decoration. VoiceOver
# publishes no accessibility tree of its own (spec 0046, part 2), so when
# VoiceOver itself is frontmost -- which `activate` makes it -- every read returns
# `missing value` and every cursor command fails. That looks exactly like a dead
# reader and is not one. Spec 0047's finding 5 is that mistake, caught. So this
# script reports what is in front, and warns when the answer is VoiceOver.
set -u

say() { printf '%-42s %s\n' "$1" "$2"; }
vo() { osascript -e "tell application \"VoiceOver\" to $1" 2>&1 | head -1; }
# The commander is the object that actually handles `perform command`.
commander() { vo "tell commander to $1"; }

if ! pgrep -qx VoiceOver; then
	echo "VoiceOver is not running. Start it (Command-F5) and run this again."
	exit 1
fi

echo "== the machine"
say "VoiceOver pid" "$(pgrep -x VoiceOver)"
say "macOS" "$(sw_vers -productVersion) ($(sw_vers -buildVersion))"

front=$(lsappinfo info -only name "$(lsappinfo front 2>/dev/null)" 2>/dev/null | sed 's/.*=//; s/"//g')
say "frontmost application" "${front:-unknown}"
if [[ "$front" == "VoiceOver" ]]; then
	echo
	echo "   WARNING: VoiceOver is frontmost, so the VO cursor is on a process that"
	echo "   publishes no accessibility tree. Reads below will look dead and are not."
	echo "   Put a real application in front and run this again."
fi

echo
echo "== enablement (both locations; Sequoia ADDED the first, it did not replace the second)"
prefs="$HOME/Library/Group Containers/group.com.apple.VoiceOver/Library/Preferences/com.apple.VoiceOver4/default.plist"
say "SCREnableAppleScript" "$(plutil -extract SCREnableAppleScript raw "$prefs" 2>/dev/null || echo 'absent')"
say ".VoiceOverAppleScriptEnabled" "$([ -e /private/var/db/Accessibility/.VoiceOverAppleScriptEnabled ] && echo present || echo absent)"

echo
echo "== the channels"
say "name (liveness)" "$(vo 'return name')"
say "content of last phrase" "$(vo 'return content of last phrase')"
say "text under cursor of vo cursor" "$(vo 'return text under cursor of vo cursor')"
say "output (speaks)" "$(vo 'output "channel probe"' || true)"

# A REAL command and a BOGUS one, because the difference is the diagnosis. Spec
# 0041 measured `Command does not exist (6)` for an unknown name; if a bogus name
# returns the SAME error as a good one, the dispatcher failed BEFORE the name was
# looked up, and no command name will work through that target.
say "commander: perform command (valid)" "$(commander 'perform command "describe item in voiceover cursor"')"
say "commander: perform command (bogus)" "$(commander 'perform command "no such command at all"')"

# THE CONTROL, and it is expected to FAIL. The application class does not handle
# `perform command` at all, so this line should show error 4 for both names on a
# perfectly healthy machine. It is here so that the two rows above can never be
# read as "the channel is down" again.
say "application: perform command (control)" "$(vo 'perform command "describe item in voiceover cursor"')"

echo
echo "== reading this"
echo "   commander: valid succeeds and bogus gives 6"
echo "       -> the command channel is HEALTHY. This is the expected result."
echo "   application: error 4 for both names"
echo "       -> also expected, on a healthy machine: that class does not handle"
echo "          the command. It is a control, not a fault."
echo "   commander: error 4 for both names"
echo "       -> now that IS a fault, and a new one: the object model is not the"
echo "          one the bridge was written against."
echo "   VoiceOver-specific calls fail with -1728/-1708 while 'name' answers"
echo "       -> the scripting object model died without the reader dying."
echo "          Nothing short of a VoiceOver restart recovers it (spec 0041)."
echo "   everything is 'missing value'"
echo "       -> check the frontmost application FIRST. A wedged app under test"
echo "          looks exactly like a dead reader from here (measured 2026-08-30:"
echo "          an unresponsive Finder, with VoiceOver entirely healthy)."
