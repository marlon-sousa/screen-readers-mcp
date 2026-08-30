#!/bin/bash
# Do VoiceOver's own modifier commands COMPOSE into a chord?
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     bash scripts/voiceover_modifiers.sh
#
# ROLE: the instrument behind lane 3's "how much input is reachable with NO
# Accessibility grant?" question, raised while implementing board entry 13.8.
#
# WHY IT MATTERS, AND WHY IT IS NOT A `typeText` QUESTION. VoiceOver's own command
# vocabulary (`SCRStringsToCommandsMap.scrconfig`, 415 entries) contains real KEYS
# as named commands -- `tab key`, `return key`, the four arrows, `f1 key` through
# `f12 key`, `delete key`, `forward delete key`, `fn key` -- plus modifiers in two
# flavours, MOMENTARY (`command key`, `shift key`, `option key`, `control key`)
# and STICKY (`toggle command key`, ...). All of them are dispatched by the reader
# over AppleEvents and cost NO Accessibility grant, which is the grant 13.8 exists
# to keep lazy. So if a modifier composes with the key that follows it, a chord
# like Option-Forward-Delete is reachable through `pressGesture` alone -- and the
# lazy lever is wider than either spec 0041 or spec 0046 claims.
#
# It does NOT change `typeText`: the table has no letter keys at all (checked by
# this script), so literal text cannot come out of it. What it changes is what
# 13.11's guidance document should tell an agent to reach for FIRST.
#
# THE PROBE IS AN OBSERVABLE EDIT, NOT A GUESS. `delete key` alone removes ONE
# CHARACTER; Option-Delete removes A WORD. Both are visible in the document's text
# over AppleScript, so composition is a comparison rather than a judgement about
# what was heard.
#
# BACKWARD delete, not forward, and that was measured rather than chosen: after
# `set text of front document`, the insertion point sits at the END of the text,
# so `forward delete key` has nothing in front of it and is a no-op -- which reads
# exactly like "the key never arrived". Measured 2026-08-30.
#
# IT IS SAFE, IN THE SAME SPECIFIC SENSE `voiceover_channels.sh` DEFINES: it
# restarts nothing, writes no preference and changes no setting. It DOES send keys
# -- that is the thing being measured -- so it sends them into a TextEdit document
# IT CREATED, which it brings to the front and refuses to proceed without, and
# which it closes WITHOUT SAVING on every exit path.
#
# THE ONE REAL HAZARD IS A MODIFIER LEFT LATCHED, and it is handled rather than
# hoped about. A sticky modifier that stays down would make every subsequent
# keystroke on the machine a chord -- so after each sticky probe this script
# releases the modifier, then PROVES it is released by deleting one character and
# checking that exactly one went. It retries, and if it cannot clear it, it says so
# in as many words instead of exiting quietly.
set -u

say() { printf '%-46s %s\n' "$1" "$2"; }
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

vo() { osascript -e "tell application \"VoiceOver\" to tell commander to perform command \"$1\"" 2>&1 | head -1; }
doc_text() { osascript -e 'tell application "TextEdit" to return text of front document' 2>/dev/null; }
reset_doc() { osascript -e 'tell application "TextEdit" to set text of front document to "alpha beta gamma"' >/dev/null 2>&1; }

PROBE='alpha beta gamma'
ONE_CHAR_GONE='alpha beta gamm'

if ! pgrep -qx VoiceOver; then
	echo "VoiceOver is not running. Start it (Command-F5) and run this again."
	exit 1
fi

echo "== the machine"
say "macOS" "$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
say "VoiceOver pid" "$(pgrep -x VoiceOver)"

echo
echo "== the vocabulary (read off this machine, not assumed)"
MAP=/System/Library/PrivateFrameworks/ScreenReader.framework/Versions/A/Resources/SCRStringsToCommandsMap.scrconfig
keys=$(plutil -convert xml1 -o - "$MAP" 2>/dev/null | grep -oE "<key>[^<]* key</key>" | sed 's/<[^>]*>//g' | sort)
say "commands whose name ends in 'key'" "$(echo "$keys" | wc -l | tr -d ' ')"
say "momentary modifiers" "$(echo "$keys" | grep -cE '^(command|shift|option|control|fn) key$')"
say "sticky modifiers" "$(echo "$keys" | grep -c '^toggle ')"
# THE BOUND THAT MATTERS FOR typeText, checked rather than asserted: if there is
# no `a key`, literal text cannot come out of this table however well it composes.
say "letter keys (a key, b key, ...)" "$(echo "$keys" | grep -cE '^[a-z] key$')"

echo
echo "== the scratch document"
if ! osascript -e 'tell application "TextEdit" to activate' \
	-e 'tell application "TextEdit" to make new document' >/dev/null 2>&1; then
	echo "TextEdit would not open a new document. Nothing was sent."
	exit 1
fi
cleanup() {
	osascript -e 'tell application "TextEdit" to close front document saving no' >/dev/null 2>&1
}
trap cleanup EXIT
sleep 1
say "frontmost application" "$(front_name) [$(front_bundle)]"
if [[ "$(front_bundle)" != "$TEXTEDIT_BUNDLE_ID" ]]; then
	echo "   REFUSING TO SEND KEYS: TextEdit is not frontmost, so they would go"
	echo "   somewhere else. Close whatever took focus and run this again."
	exit 1
fi

# The control: one plain key, so everything below is compared against a known
# effect on this machine rather than against what the manual says should happen.
echo
echo "== control: a plain key, with no modifier"
reset_doc; sleep 0.4
say "delete key" "$(vo 'delete key')"
sleep 0.6
plain=$(doc_text)
say "document now" "$plain"
if [[ "$plain" != "$ONE_CHAR_GONE" ]]; then
	echo "   The control did not behave as expected -- one character should have gone."
	echo "   Everything below would be uninterpretable, so stopping here."
	exit 1
fi

# Prove no modifier is latched, and clear it if one is. Called after every probe.
assert_clean() {
	local label="$1" attempt
	for attempt in 1 2 3; do
		reset_doc; sleep 0.4
		vo 'delete key' >/dev/null; sleep 0.6
		[[ "$(doc_text)" == "$ONE_CHAR_GONE" ]] && { say "$label: modifiers clear" "yes"; return 0; }
		vo "toggle $2 key" >/dev/null; sleep 0.4
	done
	echo
	echo "   *** A MODIFIER MAY STILL BE LATCHED ($2). Press and release it on the"
	echo "   *** keyboard, or send 'toggle $2 key' again, before typing anything."
	return 1
}
echo
echo "== the probes"
# TWO MODIFIERS, TWO FLAVOURS, FOUR RUNS. One modifier would not settle it: a
# negative could always be that particular key rather than the mechanism. The two
# chosen have edits of DIFFERENT SIZES, so a composed chord would be not merely
# different from the control but different from the other chord too --
# Option-Delete removes a word, Command-Delete removes to the start of the line.
declare -a RESULTS=()
probe() {
	local label="$1" modifier_command="$2" modifier="$3" after
	reset_doc; sleep 0.4
	say "$modifier_command" "$(vo "$modifier_command")"
	sleep 0.4
	say "delete key" "$(vo 'delete key')"
	sleep 0.6
	after=$(doc_text)
	say "document now" "${after:-<empty>}"
	RESULTS+=("$label"$'\t'"$after")
	# Release a sticky modifier before anything else happens on this machine.
	if [[ "$modifier_command" == toggle* ]]; then
		vo "$modifier_command" >/dev/null
		sleep 0.4
	fi
	assert_clean "after $label" "$modifier"
	echo
}

probe "sticky option (toggle option key)" "toggle option key" "option"
probe "momentary option (option key)" "option key" "option"
probe "sticky command (toggle command key)" "toggle command key" "command"
probe "momentary command (command key)" "command key" "command"

echo "== reading this"
for row in "${RESULTS[@]}"; do
	label=${row%%$'\t'*}
	after=${row#*$'\t'}
	if [[ "$after" == "$ONE_CHAR_GONE" ]]; then
		echo "   $label: DOES NOT COMPOSE -- one character went, exactly as with no modifier."
	elif [[ "$after" == "$PROBE" ]]; then
		echo "   $label: NOTHING HAPPENED -- the key did not reach the document at all."
	else
		echo "   $label: COMPOSED -- the edit was not a single character, so the"
		echo "      modifier was in force when the key landed. A chord is reachable"
		echo "      over AppleEvents alone, with NO Accessibility grant."
	fi
done
echo
echo "   Either way, LITERAL TEXT IS NOT REACHABLE this way: the count of letter"
echo "   keys above is what settles that, and it is why typeText synthesizes"
echo "   events and pays for the Accessibility grant to do it."
echo "   The document is closed without saving on the way out."
