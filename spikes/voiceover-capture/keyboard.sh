#!/bin/bash
# SPIKE (spec 0041 / 0043). The OTHER half of input: pressing keys in any
# application, as opposed to naming VoiceOver's own commands.
#
# It is a separate script from drive.sh on purpose, because the two differ in
# the thing that matters most about them -- what they cost the user:
#
#   drive.sh   `perform command` by English name. Needs AppleEvents access to
#              VoiceOver. The reader dispatches; nothing races for the keyboard.
#   keyboard.sh  synthesized key events. Needs ACCESSIBILITY, the widest of the
#              grants, and it types into whatever happens to be focused.
#
# Spec 0043 keeps them apart for the same reason: a bridge that never types need
# never ask for Accessibility, and that is a macOS-only design lever.
#
# Under SSH, macOS attributes the Accessibility request to
# /usr/libexec/sshd-keygen-wrapper rather than to the app that made it -- the
# consent dialog names something that looks unrelated. Granting it grants every
# SSH session on the machine.
set -uo pipefail

# The subset a screen-reader harness actually needs. Names, not magic numbers,
# because `key code 126` in a test reads as nothing at all.
key_code_for() {
	case "$1" in
	return | enter) echo 36 ;;
	tab) echo 48 ;;
	space) echo 49 ;;
	delete | backspace) echo 51 ;;
	escape | esc) echo 53 ;;
	left) echo 123 ;;
	right) echo 124 ;;
	down) echo 125 ;;
	up) echo 126 ;;
	home) echo 115 ;;
	end) echo 119 ;;
	pageup) echo 116 ;;
	pagedown) echo 121 ;;
	f1) echo 122 ;; f2) echo 120 ;; f3) echo 99 ;;  f4) echo 118 ;;
	f5) echo 96 ;;  f6) echo 97 ;;  f7) echo 98 ;;  f8) echo 100 ;;
	f9) echo 101 ;; f10) echo 109 ;; f11) echo 103 ;; f12) echo 111 ;;
	[0-9]*) echo "$1" ;;  # a raw key code, for anything not named above
	*) return 1 ;;
	esac
}

# AppleScript wants "using {command down, shift down}".
modifier_clause() {
	local parts=()
	for modifier in "$@"; do
		case "$modifier" in
		cmd | command) parts+=("command down") ;;
		ctrl | control) parts+=("control down") ;;
		opt | option | alt) parts+=("option down") ;;
		shift) parts+=("shift down") ;;
		*)
			echo "unknown modifier: $modifier" >&2
			return 1
			;;
		esac
	done
	[[ ${#parts[@]} -eq 0 ]] && return 0
	local joined
	joined=$(
		IFS=,
		echo "${parts[*]}"
	)
	echo " using {${joined//,/, }}"
}

quote() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

events() { osascript -e "tell application \"System Events\" to $1"; }

usage() {
	cat <<'USAGE'
usage: keyboard.sh <subcommand> [args]

  permission              is Accessibility granted? (asks for nothing, breaks nothing)
  type <text>             type a string into whatever is focused
  key <name> [mods...]    press a key: return tab space escape left right up down
                          home end pageup pagedown f1-f12, or a raw key code
                          modifiers: cmd ctrl opt shift
  vo <name> [mods...]     press VoiceOver's own chord -- control+option+key
  roundtrip               VERSIONED EVIDENCE: type two lines into a scratch
                          TextEdit document, read them back, close without
                          saving, and print what was sent and what arrived
USAGE
}

case "${1:-}" in
permission)
	# A key press with no modifiers into whatever is focused would be a side
	# effect. Pressing a modifier ALONE is not: it changes nothing and still
	# fails with -1002 when Accessibility is missing.
	if result=$(osascript -e 'tell application "System Events" to key down shift' \
		-e 'tell application "System Events" to key up shift' 2>&1); then
		echo "Accessibility: GRANTED (key events accepted)"
	else
		echo "Accessibility: NOT granted"
		echo "  $result"
		echo "  System Settings > Privacy & Security > Accessibility."
		echo "  Over SSH the entry to enable is sshd-keygen-wrapper."
		exit 1
	fi
	;;
type)
	shift
	events "keystroke \"$(quote "$*")\""
	;;
key | vo)
	mode="$1"
	shift
	name="${1:-}"
	shift || true
	code=$(key_code_for "$name") || {
		echo "unknown key: $name" >&2
		exit 2
	}
	if [[ "$mode" == "vo" ]]; then
		clause=$(modifier_clause control option "$@") || exit 2
	else
		clause=$(modifier_clause "$@") || exit 2
	fi
	events "key code ${code}${clause}"
	;;
roundtrip)
	# The point of this subcommand is that the checklist item "typing works" is
	# re-runnable by someone else, rather than a claim about a terminal session
	# that no longer exists. It uses a scratch TextEdit document so it types into
	# something known, and closes it without saving so it leaves nothing behind.
	sent_first="hello from the capture spike"
	sent_second="second line"
	arrived=$(osascript <<AS 2>&1
tell application "TextEdit"
	activate
	make new document
end tell
delay 1.5
tell application "System Events"
	keystroke "$sent_first"
	key code 36
	keystroke "$sent_second"
end tell
delay 1
tell application "TextEdit"
	set captured to text of front document
	close front document without saving
end tell
return captured
AS
	)
	echo "sent:     $sent_first / $sent_second"
	echo "arrived:  ${arrived//$'\n'/ / }"
	if [[ "$arrived" == "$sent_first"$'\n'"$sent_second" ]]; then
		echo "verdict:  identical"
	else
		# Expected, and the point: TextEdit autocapitalizes. "Send this keystroke"
		# is not "this text arrives", and a harness comparing typed input against
		# observed output has to expect the target application's substitutions.
		echo "verdict:  DIFFERENT -- the target application rewrote the input"
	fi
	;;
*) usage ;;
esac
