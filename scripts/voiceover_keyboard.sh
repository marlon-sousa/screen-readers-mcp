#!/bin/bash
# Does typed text arrive as typed? A re-runnable round trip through a scratch document.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     bash scripts/voiceover_keyboard.sh
#
# ROLE: the re-runnable instrument behind spec 0041's typing finding -- "the
# target application rewrites what was typed": two lines sent to TextEdit came
# back AUTOCAPITALIZED, so "send this keystroke" is not "this text arrives".
#
# IT EXISTS BECAUSE THE EVIDENCE DID NOT. Spec 0041 cites
# `spikes/voiceover-capture/keyboard.sh roundtrip`, and that file no longer
# exists: board entry 13.2 promoted the spike and only `provider/` survived. So
# the finding stood as a measurement nobody could re-run, which is exactly what
# the 2026-08-22 rule is about -- anything a check depends on is versioned, in
# the same PR as the check. This is that file, brought back beside
# `voiceover_channels.sh` and shaped like it.
#
# WHY IT IS A SEPARATE SCRIPT FROM THE GESTURE PROBE, and this is the reason
# rather than tidiness: THE TWO HALVES OF INPUT COST DIFFERENT GRANTS.
# `voiceover_channels.sh` needs only AppleEvents access to VoiceOver; this one
# needs Accessibility (`kTCCServiceAccessibility`), which is the grant board
# entry 13.8 exists to keep LAZY -- the bridge asks for it on the first
# `typeText` of a session, and since 13.17 on the first KEYSTROKE `pressGesture`
# of one, and nowhere else. Keeping the scripts apart is part of what makes "a
# session that presses only the reader's COMMAND NAMES and reads speech never
# triggered an Accessibility request" a checkable statement: you can run the
# gesture probe on a machine that has never granted Accessibility, and it works.
# `scripts/voiceover_chords.sh` is on THIS side of the line, for this reason.
# Merging the two would quietly require the wider grant to measure the narrower
# channel.
#
# IT IS SAFE, AND SAFE MEANS THE SAME SPECIFIC THING IT MEANS IN
# `voiceover_channels.sh`. It does not restart anything, does not write a
# preference and does not change a setting. It DOES type: that is the thing being
# tested, and it cannot be tested without doing it. So it types into a document
# IT CREATED, in TextEdit, which it brings to the front first -- and it closes
# that document WITHOUT SAVING, on every exit path including a failure. Nothing
# it does needs undoing, and nothing it types can land in a document somebody
# cares about.
#
# IT DOES NOT NEED VOICEOVER, and does not start or touch it. The finding is
# about the application under test rewriting input, which is true whether or not
# a screen reader is running.
#
# THE COMPARISON IS THE MEASUREMENT, AND THE TWO STRINGS ARE EXPECTED TO DIFFER.
# This script prints what was sent and what the document then contained and says
# whether they match. A difference is a finding, not a failure: autocapitalize,
# autocorrect, smart quotes and smart dashes are per-application and per-user
# settings that no bridge can see or turn off. What must never happen is a check
# somewhere ASSERTING that the two are equal -- see
# `bridges/voiceover/Sources/VoiceOverBridgeAdapters/AccessibilityTextTyper.swift`,
# whose header carries the same warning for whoever writes that comparison.
set -u

say() { printf '%-42s %s\n' "$1" "$2"; }
# THE FRONTMOST CHECK COMPARES A BUNDLE IDENTIFIER, NEVER A NAME. Measured
# 2026-08-30 on the maintainer's machine: `lsappinfo` answers with the LOCALIZED
# application name -- TextEdit is "Editor de Texto" there -- so a name comparison
# refuses to run on any machine that is not in English while reporting, wrongly,
# that the wrong application is in front. Same rule as
# `scripts/live_pages/README.md`'s: compare structure, never rendered text.
front_bundle() {
	lsappinfo info -only bundleid "$(lsappinfo front 2>/dev/null)" 2>/dev/null | sed 's/.*=//; s/"//g'
}
front_name() {
	lsappinfo info -only name "$(lsappinfo front 2>/dev/null)" 2>/dev/null | sed 's/.*=//; s/"//g'
}
TEXTEDIT_BUNDLE_ID=com.apple.TextEdit


# THE PROBE STRING. Lower case, an ordinary sentence and a second line, because
# those are what the measured substitutions act on: sentence capitalization needs
# a sentence, and the second line is what shows whether the rewrite is per line
# or per document. The quote and dash are here for the smart-substitution half.
LINE1='the quick brown fox. jumps over it.'
LINE2="a second line -- with a dash and a 'quote'"

echo "== the machine"
say "macOS" "$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
say "frontmost application (before)" "$(front_name) [$(front_bundle)]"
if [[ -n "${SSH_TTY:-}${SSH_CONNECTION:-}" ]]; then
	echo
	echo "   NOTE: this is an SSH session. macOS attributes the Accessibility"
	echo "   request to /usr/libexec/sshd-keygen-wrapper rather than to whatever"
	echo "   made it, so the consent dialog will name something that looks"
	echo "   unrelated -- and allowing it allows every SSH session on this machine."
	echo "   Spec 0041 records this because it is baffling the first time."
fi

echo
echo "== the scratch document"
# `make new document` rather than opening a file: nothing on disk is touched, and
# the document this script closes without saving is one that did not exist a
# moment ago.
if ! osascript -e 'tell application "TextEdit" to activate' \
	-e 'tell application "TextEdit" to make new document' >/dev/null 2>&1; then
	echo "TextEdit would not open a new document. Nothing was typed."
	exit 1
fi

# CLOSE IT WHATEVER HAPPENS, including on a failure below. This is the whole of
# the script's claim to being safe, so it is a trap rather than a last line.
cleanup() {
	osascript -e 'tell application "TextEdit" to close front document saving no' >/dev/null 2>&1
}
trap cleanup EXIT

# Give the window a moment to take key focus. Typed events go wherever the focus
# IS, so this pause is not politeness -- it is what stops the probe string
# landing in whatever was in front a moment ago.
sleep 1
say "frontmost application (typing into)" "$(front_name) [$(front_bundle)]"
if [[ "$(front_bundle)" != "$TEXTEDIT_BUNDLE_ID" ]]; then
	echo
	echo "   REFUSING TO TYPE: TextEdit is not frontmost, so the keystrokes would"
	echo "   go into whatever is. Close whatever took focus and run this again."
	exit 1
fi

echo
echo "== typing"
typed=$(osascript \
	-e 'tell application "System Events" to keystroke "'"$LINE1"'"' \
	-e 'tell application "System Events" to key code 36' \
	-e 'tell application "System Events" to keystroke "'"$LINE2"'"' 2>&1)
status=$?
if [[ $status -ne 0 ]]; then
	say "keystroke" "FAILED: $(echo "$typed" | head -1)"
	echo
	echo "   The usual cause is the Accessibility grant. Spec 0041 measured the"
	echo "   refusal as 'osascript is not allowed to press keys (1002)', localized"
	echo "   into the machine's own language. Recovery: System Settings > Privacy &"
	echo "   Security > Accessibility, allow the caller (see the SSH note above if"
	echo "   this is a remote session), then run this again."
	exit 1
fi
sleep 1

echo "== what arrived"
arrived=$(osascript -e 'tell application "TextEdit" to return text of front document' 2>&1)
say "sent (line 1)" "$LINE1"
say "arrived (line 1)" "$(echo "$arrived" | sed -n '1p')"
say "sent (line 2)" "$LINE2"
say "arrived (line 2)" "$(echo "$arrived" | sed -n '2p')"

echo
if [[ "$arrived" == "$LINE1"$'\n'"$LINE2" ]]; then
	echo "   IDENTICAL on this machine, with these TextEdit settings. That does NOT"
	echo "   retire the finding: the substitutions are per-application and per-user"
	echo "   preferences (Edit > Substitutions), so another machine, another user or"
	echo "   another application will differ. Nothing may assume equality."
else
	echo "   DIFFERENT, which is spec 0041's finding reproduced: the application"
	echo "   rewrote what was typed. The keystrokes went out exactly as given."
	echo "   Anything comparing typed input against observed output has to expect"
	echo "   the app's own substitutions -- autocapitalize, autocorrect, smart"
	echo "   quotes and smart dashes are all the same class."
fi
echo
echo "   The document is closed without saving on the way out; nothing was saved"
echo "   and nothing on disk was touched."
