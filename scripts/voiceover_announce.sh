#!/bin/bash
# Can the human hear the bridge while their reader is silenced?
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     bash scripts/voiceover_announce.sh [endpoint-name-or-path]
#
# ROLE: the re-runnable instrument for the one promise board entry 13.10 makes
# that NO UNIT TEST CAN CHECK -- that `announce` is AUDIBLE in a silent session,
# because it does not go through the reader. The headless tests assert that the
# words reach the synthesizer seam off a real wire frame; whether a person in the
# room actually hears them is a fact about a loudspeaker, and this is where it is
# measured. Board 13.11's live checklist executes this; 13.10 must not leave the
# claim unmeasurable.
#
# WHAT IT PROVES, IN ONE RUN, and the two halves only mean something together:
#
#   1. THE READER IS MUTE. It opens a SILENT session, presses one VoiceOver
#      command, and shows you what the reader said -- captured, indexed, and
#      inaudible. If you hear the reader at that point, silence is not working
#      and nothing else in this run means anything.
#   2. THE BRIDGE IS NOT. It then sends `announce`, which speaks with the
#      bridge's OWN synthesizer, outside VoiceOver entirely. You should hear
#      that, in a voice that is not the capture voice -- the announcer excludes
#      ours by identifier suffix, because an announcement rendered by the
#      extension that is rendering silence would be silence talking to itself.
#
# Then it asks you a question through `askUser` and collects your answer with
# `waitForUserReply`, which is the same channel in the other direction and the
# one thing in this bridge that waits on a person.
#
# IT MAKES THE MACHINE SPEAK, AND THAT IS THE THING BEING TESTED -- said plainly
# because the sibling probes are read as safe by default. `voiceover_focus.sh` is
# read-only; this one is not silent and cannot be: a channel cannot be tested
# without using it.
#
# WHAT IT DOES TO THE MACHINE, exactly, and what needs undoing:
#
#   * It opens a SILENT session, so your reader goes quiet for the length of the
#     run. That is a LEASE, not a state: `bye` releases it, and if this script is
#     killed the marker expires on its own and the machine speaks again without
#     anything running (13.6, hard invariant 3 in its macOS form).
#   * It presses ONE VoiceOver command -- `describe item in voiceover cursor` by
#     default -- which describes what the cursor is already on and moves nothing.
#   * It types nothing, so it needs no Accessibility grant and raises no consent
#     dialog. Pressing a command is an AppleEvent; that is 13.8's whole lever.
#   * It writes no preference. The bridge itself selects the capture voice at the
#     handshake and puts your own voice back on every teardown path.
#
# IT NEEDS A BRIDGE ALREADY LISTENING, which is the one thing it will not start
# for you: the bridge is either the .app's control dialog with Start pressed, or
# `swift build --product BridgeListener && .build/debug/BridgeListener`. A script
# that started one would be measuring a bridge nobody configured.
set -u

ENDPOINT="${1:-voiceoverMcpBridge}"
if [[ "$ENDPOINT" == */* ]]; then
	SOCKET="$ENDPOINT"
elif [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
	SOCKET="$XDG_RUNTIME_DIR/screenreader-mcp/$ENDPOINT.sock"
else
	SOCKET="$HOME/.screenreader-mcp/$ENDPOINT.sock"
fi

say() { printf '%-42s %s\n' "$1" "$2"; }

echo "== the machine"
say "macOS" "$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
if pgrep -qx VoiceOver; then
	say "VoiceOver pid" "$(pgrep -x VoiceOver)"
else
	echo "VoiceOver is not running. Start it (Command-F5) and run this again:"
	echo "half of what this measures is that the READER goes quiet."
	exit 1
fi
say "endpoint" "$SOCKET"
if [[ ! -S "$SOCKET" ]]; then
	echo
	echo "Nothing is listening there. Start the bridge first -- the .app's control"
	echo "dialog and press Start, or:"
	echo "    swift build --package-path bridges/voiceover --product BridgeListener"
	echo "    bridges/voiceover/.build/debug/BridgeListener"
	exit 1
fi

# The session itself, in Python because bash cannot hold a conversation over a
# unix socket: it has to read each reply before it knows what to send next -- the
# ticket `askUser` mints is the whole point of `waitForUserReply`.
#
# THE PROGRAM IS PASSED WITH -c SO THAT STDIN STAYS THE TERMINAL, and that is a
# bug fix rather than a flourish. It was `python3 - <<'PY'`, which tells Python to
# read the PROGRAM from stdin -- so by the time the program ran stdin was
# exhausted, and the `input()` below could only ever raise `EOFError`. Measured
# 2026-08-31, the first time anybody ran this script to completion: it died at
# step 1 on the maintainer's own machine, before the announcement it exists to
# measure, and it would have died the same way in any terminal.
#
# `python3 /dev/fd/3 3<<'PY'` WAS TRIED FIRST AND IS WRONG ON macOS: bash backs a
# heredoc with a temp file, and re-opening it through /dev/fd yields an EMPTY
# program -- Python exits 0 having run nothing, which is the worst possible
# failure for a check, because the script goes on to print its closing summary as
# though it had measured something. Measured the same day. A command-line program
# has no such subtlety and leaves fd 0 alone.
PROGRAM=$(cat <<'PY'
import json
import socket
import sys
import time

path = sys.argv[1]
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect(path)
lines = sock.makefile("rwb")
counter = 0


def call(cmd, **params):
	global counter
	counter += 1
	lines.write((json.dumps({"id": counter, "cmd": cmd, "params": params}) + "\n").encode())
	lines.flush()
	reply = json.loads(lines.readline())
	if "error" in reply and reply["error"]:
		print(f"   {cmd} FAILED: {reply['error'].get('message', reply['error'])}")
		return None
	return reply.get("result", {})


print()
print("== the handshake, in SILENT mode")
hello = call("hello", protocolVersion=1, mode="silent", persona="")
if hello is None:
	# A refusal here IS the diagnosis: the handshake names the condition and its
	# recovery rather than establishing a session that quietly means something
	# else (13.6).
	print("   the bridge refused a silent session, and the message above says why.")
	sys.exit(1)
print(f"   reader {hello['reader']['name']} {hello['reader']['version']}, synth {hello['synth']}")
print(f"   capabilities: {', '.join(hello['capabilities'])}")
if "interact" not in hello["capabilities"]:
	print("   this build does not announce `interact`; there is nothing to measure.")
	sys.exit(1)

print()
print("== 1. the READER should be inaudible")
# A HUMAN GETS THE PROMPT; ANYTHING ELSE GETS A COUNTDOWN. `poe live` may be run
# from a wrapper with no terminal on stdin, and a script that CRASHED there would
# report a failure of the bridge when what failed was the harness -- which is
# exactly what happened before the fd-3 fix above. Neither path skips the pause:
# its whole purpose is that somebody is listening when the reader is asked to
# speak.
if sys.stdin.isatty():
	input("   press return, then LISTEN -- you should hear nothing from VoiceOver: ")
else:
	print("   no terminal on stdin; listening in 5 seconds -- you should hear NOTHING")
	time.sleep(5)
pressed = call(
	"pressGesture", gestures=["describe item in voiceover cursor"], graceMs=1500, announce=""
)
if pressed is not None:
	said = [entry["text"] for entry in pressed.get("speech", [])]
	print(f"   the reader said {len(said)} utterance(s), captured and not heard:")
	for text in said:
		print(f"     {text!r}")
	if not said:
		print("     (nothing arrived -- see ProviderState in the bridge's own output)")

print()
print("== 2. the BRIDGE should be audible, in a voice that is not the capture voice")
call("announce", text="This is the bridge speaking, outside VoiceOver.")
print("   sent. You should have heard that sentence out loud.")

print()
print("== 3. and the channel the other way: a question you answer")
asked = call("askUser", prompt="Did you hear the bridge speak while VoiceOver stayed quiet?")
if asked is not None:
	ticket = asked["ticket"]
	print(f"   a window is on your screen (ticket {ticket}). Answer it.")
	answered = False
	# The window's own deadline is 300 s; each poll is bounded separately, which
	# is exactly why this is a loop rather than one long wait.
	for _ in range(10):
		reply = call("waitForUserReply", ticket=ticket, timeout=30)
		if reply is None:
			break
		if reply["answered"]:
			print(f"   you answered: {reply['text']!r}")
			answered = True
			break
		print("   still waiting...")
	if not answered:
		print("   no answer collected (the window expired or was dismissed).")

print()
print("== ending the session, which puts your reader and your voice back")
call("bye")
sock.close()
PY
)
python3 -c "$PROGRAM" "$SOCKET"

echo
# Single quotes, deliberately: the sentence contains backticks, and in double
# quotes bash would try to RUN `announce`.
echo 'The claim: `announce` is audible in a silent session BECAUSE it does not go'
echo 'through the reader. Step 1 silent and step 2 audible is that claim measured;'
echo 'either one alone is not.'
