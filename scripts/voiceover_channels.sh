#!/bin/bash
# Which of VoiceOver's AppleScript channels are alive on this machine?
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     bash scripts/voiceover_channels.sh
#
# ROLE: the re-runnable instrument behind spec 0047's finding 4. That finding --
# that `perform command` fails with error 4 for EVERY command while every read
# channel answers normally -- is a risk to board entry 13.7, which puts the whole
# gesture capability on `perform command`. A risk nobody can re-measure is a risk
# nobody can close, which is the 2026-08-22 fixture rule applied to a reader
# instead of a web page.
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

say() { printf '%-34s %s\n' "$1" "$2"; }
vo() { osascript -e "tell application \"VoiceOver\" to $1" 2>&1 | head -1; }

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
# now returns the same error as a good one, the dispatcher failed BEFORE the name
# was looked up, and no command name will work.
say "perform command (valid)" "$(vo 'perform command "describe item in voiceover cursor"')"
say "perform command (bogus)" "$(vo 'perform command "no such command at all"')"

echo
echo "== reading this"
echo "   reads answer + commands fail identically for valid and bogus"
echo "       -> the command channel is down; spec 0047 finding 4. 13.7 is affected."
echo "   bogus gives 6 and valid succeeds  -> the channel is healthy."
echo "   everything is 'missing value'     -> check the frontmost application first."
