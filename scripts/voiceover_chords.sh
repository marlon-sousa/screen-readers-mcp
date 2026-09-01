#!/bin/bash
# Can a chord be pressed on THIS machine's keyboard layout?
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     bash scripts/voiceover_chords.sh
#
# ROLE: the versioned instrument board entries 13.17 and 13.19 owe -- the one a
# live checklist cites instead of a measurement nobody can re-run (the rule
# AGENTS.md records from 2026-08-22).
#
# WHAT IT ANSWERS. Until 13.17 this bridge could dispatch VoiceOver's own command
# names and could type literal text, and could not press Command-L -- which is
# how everybody actually uses a Mac. The gap was OURS rather than the platform's:
# Core Graphics sends chords perfectly well given a virtual keycode and modifier
# flags. THE HARD PART IS WHICH KEYCODE. Which physical key produces `l` depends
# on the layout the person is typing on, and the maintainer's is Brazilian -- so a
# hard-coded ANSI table would pass review and press the wrong key on his machine.
# This script shows the numbers the LIVE LAYOUT answers with, and then presses a
# chord with them so the result is an observable edit rather than a claim.
#
# THE PROBE IS AN OBSERVABLE EDIT, in the shape `voiceover_modifiers.sh` uses:
# Command-A selects everything in a scratch document, so the Delete that follows
# empties it. If the chord did NOT compose, only one character goes -- and the two
# outcomes are different strings rather than different feelings about what was
# heard.
#
# IT IS SAFE IN THE SAME SPECIFIC SENSE THE OTHER PROBES ARE: it restarts
# nothing, writes no preference and changes no setting. It DOES post real key
# events -- that is the thing being measured -- so it sends them into a TextEdit
# document IT CREATED, which it brings to the front and refuses to proceed
# without, and which it closes WITHOUT SAVING on every exit path including a
# failure. It presses no destructive chord: never Command-Q, Command-W or
# Command-Shift-Q, whatever happens to be running.
#
# IT NEEDS THE ACCESSIBILITY GRANT, and that is why it is a separate script from
# `voiceover_modifiers.sh` -- the same split as `voiceover_keyboard.sh` and for
# the same reason. The gesture probes run on a machine that has never granted
# Accessibility; this one cannot, because posting a key event without the grant
# is dropped by the window server with nothing said anywhere. If the document
# does not change and no error appears, suspect the grant first.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESS="$HERE/voiceover_chord_press.swift"

say() { printf '%-46s %s\n' "$1" "$2"; }
front_bundle() {
	lsappinfo info -only bundleid "$(lsappinfo front 2>/dev/null)" 2>/dev/null | sed 's/.*=//; s/"//g'
}
# THE FRONTMOST CHECK COMPARES A BUNDLE IDENTIFIER, NEVER A NAME -- TextEdit is
# "Editor de Texto" on the maintainer's machine, so a name comparison refuses to
# run on any machine that is not in English while reporting the wrong reason.
front_name() {
	lsappinfo info -only name "$(lsappinfo front 2>/dev/null)" 2>/dev/null | sed 's/.*=//; s/"//g'
}
TEXTEDIT_BUNDLE_ID=com.apple.TextEdit
doc_text() { osascript -e 'tell application "TextEdit" to return text of front document' 2>/dev/null; }
reset_doc() { osascript -e 'tell application "TextEdit" to set text of front document to "alpha beta gamma"' >/dev/null 2>&1; }

PROBE='alpha beta gamma'
ONE_CHAR_GONE='alpha beta gamm'
# What the caret sits at the end of the reset text produces when `h` is pressed
# with no modifier at all -- 13.19's shape.
LETTER_ADDED='alpha beta gammah'

echo "== the machine"
say "macOS" "$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
say "Accessibility grant (this process)" \
	"$(osascript -e 'tell application "System Events" to return UI elements enabled' 2>/dev/null || echo unknown)"

echo
echo "== the layout, read the way the bridge reads it"
# SAFE ANYWHERE: this half presses nothing. It is the half worth running on a
# machine whose layout you want to know about without touching its keyboard.
swift "$PRESS" report a l f t 4 '$' '\' 'ç'

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

# The control first, so everything below is compared against a known effect on
# this machine rather than against what the documentation says should happen.
echo
echo "== control: the Delete key alone, with no modifier"
reset_doc; sleep 0.5
swift "$PRESS" press backspace >/dev/null
sleep 0.6
plain=$(doc_text)
say "document now" "${plain:-<empty>}"
if [[ "$plain" != "$ONE_CHAR_GONE" ]]; then
	echo "   The control did not behave as expected -- one character should have gone."
	echo "   If NOTHING changed, this process almost certainly lacks the Accessibility"
	echo "   grant: an event posted without it is dropped with no error anywhere."
	echo "   Everything below would be uninterpretable, so stopping here."
	exit 1
fi

# 13.19: THE SAME PRESS WITH NO MODIFIERS AT ALL, which is what `kb:h` posts.
# Until that entry a lone key had no notation on this bridge -- the `+` was the
# whole discriminator, so `h` was looked up as one of the reader's command names
# and refused, while an ordinary user with single-key Quick Nav on presses it to
# move by heading. This half proves the MECHANICAL claim: an unmodified keycode
# press arrives, and holds nothing down afterwards. Whether Quick Nav answers it
# is the live checklist's question, because that needs the reader and a page.
echo
echo "== an unmodified key: the letter h, which is what kb:h presses"
reset_doc; sleep 0.5
swift "$PRESS" press h
sleep 0.6
letter=$(doc_text)
say "document now" "${letter:-<empty>}"
if [[ "$letter" == "$LETTER_ADDED" ]]; then
	echo "   THE LETTER ARRIVED, on the keycode this layout answered with. That is"
	echo "   the event kb:h posts, and no modifier went down or had to come up."
elif [[ "$letter" == "$PROBE" ]]; then
	echo "   NOTHING REACHED THE DOCUMENT. Suspect the Accessibility grant -- though"
	echo "   the control above should already have caught that."
else
	echo "   SOMETHING ELSE ARRIVED, which is worth reporting verbatim: the document"
	echo "   reads '$letter' rather than '$LETTER_ADDED'."
fi

echo
echo "== the probe: Command-A, then Delete"
reset_doc; sleep 0.5
swift "$PRESS" press command a
sleep 0.5
swift "$PRESS" press backspace >/dev/null
sleep 0.6
after=$(doc_text)
say "document now" "${after:-<empty>}"

# THE ASSERTION `voiceover_modifiers.sh` ALREADY HAD, AND THIS SCRIPT DID NOT ON
# ITS FIRST RUN. That script's header warns that "a sticky modifier that stays
# down would make every subsequent keystroke on the machine a chord", and that is
# exactly what happened here: the first implementation posted modifier FLAGS and
# no transitions, delivered the chord, and left Command held on the maintainer's
# machine -- after which typing silently went nowhere, with no error anywhere.
# So the control is repeated AFTER the chord: one plain Delete must remove exactly
# one character, as it did before.
echo
echo "== proving the keyboard is clean again"
reset_doc; sleep 0.5
swift "$PRESS" press backspace >/dev/null
sleep 0.6
clean=$(doc_text)
say "one plain Delete now leaves" "${clean:-<empty>}"
if [[ "$clean" != "$ONE_CHAR_GONE" ]]; then
	echo "   *** A MODIFIER IS STILL HELD. Press and release Command, Shift, Option and"
	echo "   *** Control on the keyboard before typing anything else -- every keystroke"
	echo "   *** on this machine is a chord until you do."
fi

echo
echo "== reading this"
if [[ -z "$after" ]]; then
	echo "   THE CHORD WORKED. Command-A selected the whole document, so the Delete"
	echo "   that followed emptied it -- on this layout, with the keycode printed"
	echo "   above. That is a chord this bridge could not send before 13.17."
elif [[ "$after" == "$ONE_CHAR_GONE" ]]; then
	echo "   THE CHORD DID NOT COMPOSE: one character went, exactly as with no"
	echo "   modifier, so the Command flag was not in force when the key landed."
elif [[ "$after" == "$PROBE" ]]; then
	echo "   NOTHING REACHED THE DOCUMENT AT ALL. Suspect the Accessibility grant"
	echo "   before suspecting the keycode -- the control above should have caught"
	echo "   that, so this is the stranger of the two failures."
else
	echo "   SOMETHING ELSE HAPPENED, which is the outcome worth reporting verbatim:"
	echo "   the document reads '$after' rather than empty or '$ONE_CHAR_GONE'."
fi
echo
echo "   The document is closed without saving on the way out."
