#!/bin/bash
# SPIKE (spec 0041). The INPUT half: driving VoiceOver from outside, and reading
# back what it said.
#
# Everything here goes through AppleScript. Nothing injects keystrokes, which
# matters more than it looks: key injection needs the posting process to hold
# Accessibility permission (TCC), and it races with whatever else has the
# keyboard. `perform command` names the command instead, so the reader does the
# dispatch -- the macOS analogue of the bridge's gesture port, and a better one.
#
# The command vocabulary is not documented; it is a table inside VoiceOver:
#   /System/Library/PrivateFrameworks/ScreenReader.framework/Versions/A/Resources/SCRStringsToCommandsMap.scrconfig
# 415 entries on macOS 15.0, mapping an English phrase to an internal selector.
# `./drive.sh commands [pattern]` reads it, so the list is never guessed.
#
# Requires: VoiceOver running, and "Allow VoiceOver to be controlled with
# AppleScript" enabled (spec 0041, E3).
set -uo pipefail

MAP=/System/Library/PrivateFrameworks/ScreenReader.framework/Versions/A/Resources/SCRStringsToCommandsMap.scrconfig

vo() { osascript -e "tell application \"VoiceOver\" to $1"; }

# Escapes a string for embedding in AppleScript source.
quote() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

usage() {
	cat <<'USAGE'
usage: drive.sh <subcommand> [args]

  last                    what VoiceOver last said (the ONLY read-back there is)
  cursor                  text under the VoiceOver cursor
  kbcursor                text under the keyboard cursor (a DIFFERENT cursor)
  say <text>              make VoiceOver speak text
  command <name>          perform a VoiceOver command by its English name
  move <direction>        up | down | left | right | in | out
  commands [pattern]      list the command vocabulary, optionally filtered
  walk <n> [direction]    move n times, printing what was said after each step
  latency <n>             how long after a command does `last phrase` change?
USAGE
}

case "${1:-}" in
last) vo 'return content of last phrase' ;;
cursor) vo 'return text under cursor of vo cursor' ;;
kbcursor) vo 'return text under cursor of keyboard cursor' ;;
say)
	shift
	vo "output \"$(quote "$*")\""
	;;
command)
	shift
	vo "tell commander to perform command \"$(quote "$*")\""
	;;
move)
	case "${2:-}" in
	up | down | left | right) vo "tell vo cursor to move ${2}" ;;
	in) vo 'tell vo cursor to move into item' ;;
	out) vo 'tell vo cursor to move out of item' ;;
	*)
		echo "move needs: up|down|left|right|in|out" >&2
		exit 2
		;;
	esac
	;;
commands)
	if [[ -n "${2:-}" ]]; then
		plutil -p "$MAP" | grep -i "$2"
	else
		plutil -p "$MAP" | grep '=>'
	fi
	;;
walk)
	count="${2:-5}"
	direction="${3:-right}"
	for ((step = 1; step <= count; step++)); do
		vo "tell vo cursor to move ${direction}" >/dev/null
		printf '%d\t%s\n' "$step" "$(vo 'return content of last phrase' | tr '\n' ' ')"
	done
	;;
latency)
	# Probe D1's mechanism in miniature: issue a move, then poll `last phrase`
	# until it changes, reporting how long that took and how many polls it cost.
	count="${2:-5}"
	for ((step = 1; step <= count; step++)); do
		before="$(vo 'return content of last phrase')"
		start=$(python3 -c 'import time; print(time.time())')
		vo 'tell vo cursor to move right' >/dev/null
		polls=0
		while :; do
			polls=$((polls + 1))
			now="$(vo 'return content of last phrase')"
			[[ "$now" != "$before" ]] && break
			[[ $polls -gt 200 ]] && break
		done
		python3 -c "import sys,time; print(f'{int(sys.argv[1])}\t{(time.time()-float(sys.argv[2]))*1000:.0f} ms\t{sys.argv[3]} polls\t{sys.argv[4][:60]}')" \
			"$step" "$start" "$polls" "$now"
	done
	;;
*) usage ;;
esac
