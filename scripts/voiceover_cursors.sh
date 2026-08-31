#!/bin/bash
# How far apart do the VoiceOver cursor and keyboard focus actually get?
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     bash scripts/voiceover_cursors.sh [command-name]
#
# ROLE: the measurement board entry 13.9 owed and could not take, and the one
# 13.11's guidance document needs before it can tell an agent which cursor to
# reach for. VoiceOver's dictionary exposes a `vo cursor` and a separate
# `keyboard cursor`, each with its own `text under cursor`, and spec 0046 records
# that they are "two views that only usually agree" -- a claim nobody in this
# repo had re-measured. `getFocusInfo` answers from the KEYBOARD/accessibility
# view; an agent that wants what the user HEARS uses
# pressGesture ["describe item in voiceover cursor"] and reads the captured
# speech. This script is where the difference between those two becomes visible.
#
# WHY IT IS A SEPARATE SCRIPT FROM `voiceover_focus.sh`, and this is the reason
# rather than tidiness -- the same split, for the same kind of reason, as
# `voiceover_channels.sh` and `voiceover_keyboard.sh`:
#
#   * `voiceover_focus.sh` is READ-ONLY. It presses nothing, and it answers "what
#     does each route say right now".
#   * THIS ONE PRESSES. A disagreement between the cursors cannot be observed by
#     waiting for one; it has to be provoked, by moving the VoiceOver cursor
#     while keyboard focus stays put. Merging the two would make the read-only
#     claim untrue for the probe that depends on it.
#
# IT NEEDS BOTH GRANTS, and that is worth knowing before running it: Automation
# (to send AppleEvents to VoiceOver and to TextEdit) for the press, and
# Accessibility for the tree column. The read-only probe needs only the second.
#
# WHAT IT DOES TO THE MACHINE, exactly, and what needs undoing:
#
#   * It creates a NEW TextEdit document -- nothing on disk is opened -- puts two
#     lines of plain text in it by AppleScript, and CLOSES IT WITHOUT SAVING on
#     every exit path including a failure. That is a `trap`, not a last line.
#   * It sets the document's text with `set text of front document`, which is an
#     application command and NOT synthesized typing: no Accessibility grant is
#     spent on it, and none of spec 0041's autocapitalization class applies,
#     because nothing here compares what was sent with what arrived.
#   * It presses ONE VoiceOver command, `move right` by default -- which moves
#     the VOICEOVER cursor and not keyboard focus, which is the whole point. That
#     is the same thing pressing VO-Right does, and it needs no undoing.
#   * It restarts nothing, writes no preference, and changes no setting.
#
# THE COMMAND NAME IS AN ARGUMENT, WITH ONE DEFAULT, and there is deliberately no
# list of them here: the vocabulary is the READER's -- 415 English command names
# on macOS 15.0 -- this repo keeps no copy of it that could go stale, and an
# unknown name costs one round trip and answers `Command does not exist (6)`.
# Measured 2026-08-30 on the maintainer's machine: `move right`, `move left`,
# `go to menu bar`, `go to dock`, `go to desktop` and `stop interacting with
# item` are real; `move to next item`, `move to window` and `go to window` are
# not.
#
# THE DEFAULT IS `stop interacting with item` BECAUSE `move right` DOES NOT SHOW
# IT, and that negative is worth keeping rather than discarding. Measured
# 2026-08-30: inside a text area, `move right` moves the VoiceOver cursor WITHIN
# the element, and `text under cursor` reports the whole element -- so both
# cursors go on answering the same string and the run looks like agreement when
# nothing was tested. What separates them is a move that changes WHICH ELEMENT
# the cursor is on. Pass `move right` as the argument to see the negative
# reproduce.
set -u

MOVE="${1:-stop interacting with item}"

say() { printf '%-38s %s\n' "$1" "$2"; }
vo() { osascript -e "tell application \"VoiceOver\" to $1" 2>&1 | head -1; }
commander() { vo "tell commander to $1"; }
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

front_ref() { lsappinfo front 2>/dev/null; }
front_field() {
	lsappinfo info -only "$1" "$(front_ref)" 2>/dev/null | sed 's/.*=//; s/"//g'
}

if ! command -v swift >/dev/null 2>&1; then
	echo "This probe needs the Swift toolchain (xcode-select --install). Nothing was done."
	exit 1
fi
if ! pgrep -qx VoiceOver; then
	echo "VoiceOver is not running. Start it (Command-F5) and run this again."
	exit 1
fi

echo "== the machine"
say "macOS" "$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
say "VoiceOver pid" "$(pgrep -x VoiceOver)"
say "the command this run presses" "$MOVE"

echo
echo "== the scratch document"
if ! osascript -e 'tell application "TextEdit" to activate' \
	-e 'tell application "TextEdit" to make new document' \
	-e 'tell application "TextEdit" to set text of front document to "alpha one
bravo two"' >/dev/null 2>&1; then
	echo "TextEdit would not open a new document. Nothing was pressed."
	exit 1
fi

# CLOSE IT WHATEVER HAPPENS. This is the whole of the script's claim to being
# safe, so it is a trap rather than a last line.
cleanup() {
	osascript -e 'tell application "TextEdit" to close front document saving no' >/dev/null 2>&1
}
trap cleanup EXIT

# Let the window take key focus before anything is read: a snapshot taken while
# focus is still moving measures the previous application.
sleep 1
say "frontmost application" "$(front_field name) [$(front_field bundleid)]"

# One snapshot of all three views, as close to one instant as a shell gets.
snapshot() {
	local label="$1" pid ax
	pid=$(front_field pid)
	ax=$(swift "$here/voiceover_ax_focus.swift" "${pid:-0}" 2>&1)
	echo
	echo "== $label"
	say "frontmost pid" "${pid:-unknown}"
	say "tree: AXRole" "$(printf '%s\n' "$ax" | awk -F'\t' '$1=="AXRole" {print $2}')"
	say "tree: AXValue" "$(printf '%s\n' "$ax" | awk -F'\t' '$1=="AXValue" {print $2}')"
	say "tree: AXFocused" "$(printf '%s\n' "$ax" | awk -F'\t' '$1=="AXFocused" {print $2}')"
	say "vo cursor" "$(vo 'return text under cursor of vo cursor')"
	say "keyboard cursor" "$(vo 'return text under cursor of keyboard cursor')"
}

snapshot "before: nothing has been pressed"

echo
echo "== pressing '$MOVE' -- this moves the VOICEOVER cursor, not keyboard focus"
result=$(commander "perform command \"$MOVE\"")
if [[ -n "$result" ]]; then
	say "the reader answered" "$result"
	echo "   Error 6 means this reader has no command by that name -- the vocabulary"
	echo "   is the reader's own and this repo keeps no copy of it. Pass a name as"
	echo "   the first argument. Nothing moved."
else
	say "the reader answered" "(nothing, which is success)"
fi
sleep 1

snapshot "after: one press"

echo
echo "== reading this"
echo "   the two cursors now DIFFER"
echo "       -> the measurement. VoiceOver's cursor moved and keyboard focus did"
echo "          not, which is exactly the state an agent has to be able to tell"
echo "          apart: getFocusInfo answers the KEYBOARD view, and"
echo "          pressGesture [\"describe item in voiceover cursor\"] plus a speech"
echo "          read answers what the user HEARS."
echo "   they still AGREE"
echo "       -> either the press did nothing (check the reader's answer above), or"
echo "          it moved the cursor WITHIN one element, which 'text under cursor'"
echo "          cannot show -- that is what 'move right' does inside a text area."
echo "   the vo cursor answers a LOCALIZED string"
echo "       -> measured 2026-08-30: it answered 'area de rolagem', which is a"
echo "          role rendered in the machine's own language, where the tree's"
echo "          AXRole is 'AXTextArea' on every machine. That is a second reason"
echo "          getFocusInfo prefers the tree, beyond it being richer: the cursor"
echo "          route's name is not comparable across machines."
echo "   the tree column tracks the KEYBOARD cursor and not the vo cursor"
echo "       -> expected, and it is the whole reason getFocusInfo answers from the"
echo "          tree: they are the same view of the machine."
echo
echo "   The document is closed without saving on the way out; nothing was saved,"
echo "   nothing on disk was touched, and the VoiceOver cursor was moved exactly"
echo "   as pressing VO-Right moves it."
