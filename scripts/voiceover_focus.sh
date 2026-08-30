#!/bin/bash
# Where is the focus? The same question down both of the bridge's routes, side by side.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     bash scripts/voiceover_focus.sh
#
# ROLE: the re-runnable instrument behind spec 0047's finding 8 -- "the
# accessibility API drives the reader's own settings, with two traps" -- whose
# AX work that finding calls "a working prototype of entry 13.9's
# AXAccessibilityTree adapter". It also carries finding 5, the confound that
# reads exactly like a dead reader, because that one is only visible from here.
#
# IT EXISTS BECAUSE THE EVIDENCE DID NOT. The `axpress` helper those findings
# were made with lived in a session that no longer exists -- exactly like spec
# 0041's `keyboard.sh` did before 13.8 brought it back as
# `scripts/voiceover_keyboard.sh`. A measurement nobody can re-run is weaker than
# it looks (the 2026-08-22 rule), and this lane's substitute for a CI test on the
# reader edge is a check somebody can run again.
#
# WHAT IT SHOWS, AND WHY IT IS SIDE BY SIDE. `getFocusInfo` answers from the
# ACCESSIBILITY TREE when this process holds the Accessibility grant and from the
# VOICEOVER CURSOR when it does not (spec 0046's 13.9 section). Those are two
# views of one machine that only USUALLY agree, and nobody in this repo has
# re-measured how far apart they get. So both are read here, in one pass, at one
# instant -- plus the `keyboard cursor`, which is the third view and the one the
# board says 13.11's guidance has to tell an agent about. A disagreement between
# the three columns is the finding; the script is where it becomes visible.
#
# IT IS SAFE, AND SAFE MEANS SOMETHING SPECIFIC HERE, as it does in
# `voiceover_channels.sh` and `voiceover_keyboard.sh`. This one is stronger than
# either: it is READ-ONLY. It presses nothing, types nothing, restarts nothing,
# writes no preference and changes no setting. It does not even make VoiceOver
# speak -- the channels probe uses `output` and `describe item`, and this does
# not need to. Nothing it does needs undoing.
#
# AND IT NEVER REQUESTS THE ACCESSIBILITY GRANT. `AXIsProcessTrusted` asks
# nobody anything; `AXIsProcessTrustedWithOptions` with the prompt option raises
# a system consent dialog and leaves the caller on a list that stays granted,
# with no undo. The bridge requests that grant from exactly one place -- a
# `typeText` -- and an instrument that requested it would make the claim untrue
# for anyone who ran the instrument. So this script reports the grant and stops.
#
# THE -25204 CONTROL IS EXPECTED TO FAIL, and it is kept for the reason
# `voiceover_channels.sh` keeps the application-target probe: a measurement that
# fails on a healthy machine, so that nobody rediscovers it as a fault.
# `AXUIElementCreateSystemWide()` is the obvious way to ask "what is focused
# anywhere", and asking it returns -25204 `kAXErrorCannotComplete`. That is NOT
# `kAXErrorAPIDisabled` (-25211), so no permission fixes it and nobody may "fix"
# it with one -- which is why the bridge addresses
# `AXUIElementCreateApplication(pid)` instead.
set -u

say() { printf '%-42s %s\n' "$1" "$2"; }

if ! command -v swift >/dev/null 2>&1; then
	echo "This probe needs the Swift toolchain (xcode-select --install). Nothing was read."
	exit 1
fi

echo "== the machine"
say "macOS" "$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
if pgrep -qx VoiceOver; then
	say "VoiceOver pid" "$(pgrep -x VoiceOver)"
else
	say "VoiceOver" "NOT RUNNING -- the cursor columns below will fail; the tree column will not"
fi

# THE FRONTMOST APPLICATION IS PART OF THE MEASUREMENT, twice over. The tree
# route is addressed to its pid, and finding 5 is about what happens when the
# answer is VoiceOver itself. THE BUNDLE IDENTIFIER IS WHAT IS COMPARED: the
# name is localized -- TextEdit is "Editor de Texto" on the maintainer's machine
# -- and this lane compares structure, never rendered text.
front_ref=$(lsappinfo front 2>/dev/null)
front_name=$(lsappinfo info -only name "$front_ref" 2>/dev/null | sed 's/.*=//; s/"//g')
front_bundle=$(lsappinfo info -only bundleid "$front_ref" 2>/dev/null | sed 's/.*=//; s/"//g')
front_pid=$(lsappinfo info -only pid "$front_ref" 2>/dev/null | sed 's/.*=//; s/"//g')
say "frontmost application" "${front_name:-unknown} [${front_bundle:-none}]"
say "frontmost pid" "${front_pid:-unknown}"
if [[ "$front_bundle" == "com.apple.VoiceOver"* || "$front_name" == "VoiceOver" ]]; then
	echo
	echo "   WARNING: VoiceOver is frontmost. It publishes NO accessibility tree of"
	echo "   its own, so the tree column will be empty and the cursor sits on a"
	echo "   process with nothing to read. That looks exactly like a dead reader and"
	echo "   is not one -- spec 0047, finding 5. Put a real application in front."
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The AX half, in the language the bridge's own adapter uses. It is here rather
# than in `osascript` because System Events cannot create the SYSTEM-WIDE element
# the control below needs, and because this is the API `AXAccessibilityTree`
# actually calls -- an instrument that measured a different API would be evidence
# about something else.
cat > "$work/focus.swift" <<'SWIFT'
import ApplicationServices
import Foundation

func render(_ value: CFTypeRef) -> String {
	let type = CFGetTypeID(value)
	if type == CFStringGetTypeID() { return unsafeBitCast(value, to: CFString.self) as String }
	if type == CFBooleanGetTypeID() {
		return CFBooleanGetValue(unsafeBitCast(value, to: CFBoolean.self)) ? "true" : "false"
	}
	if type == CFNumberGetTypeID() {
		var number = 0.0
		CFNumberGetValue(unsafeBitCast(value, to: CFNumber.self), .doubleType, &number)
		return String(number)
	}
	return "<\(CFCopyTypeIDDescription(type) as String? ?? "opaque")>"
}

// ASKS NOBODY ANYTHING. The option that prompts is deliberately not used here --
// see the script's header.
print("trusted\t\(AXIsProcessTrusted() ? "yes" : "no")")

// THE CONTROL. Expected to fail with -25204 on a perfectly healthy machine.
var wide: CFTypeRef?
let wideStatus = AXUIElementCopyAttributeValue(
	AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &wide)
print("systemwide\t\(wideStatus.rawValue)")

guard CommandLine.arguments.count > 1, let pid = Int32(CommandLine.arguments[1]) else {
	print("focused\tno pid given")
	exit(0)
}
var focused: CFTypeRef?
let status = AXUIElementCopyAttributeValue(
	AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &focused)
guard status == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
	// -25212 is kAXErrorNoValue: nothing is focused there. AN ANSWER, not a
	// fault -- see the script's header and spec 0047's finding 5.
	let named = status.rawValue == -25212 ? "nothing focused (kAXErrorNoValue -25212)"
		: "nothing (AXError \(status.rawValue))"
	print("focused\t\(named)")
	exit(0)
}
print("focused\tyes")
let element = unsafeBitCast(focused, to: AXUIElement.self)
// The list the bridge asks for, plus AXSubrole for interest -- and
// AXRoleDescription, which the bridge deliberately NEVER asks for: it is AXRole
// rendered into the user's language, and on a Portuguese machine it is what
// would silently make `role` mean something different here than elsewhere.
for name in [
	"AXRole", "AXSubrole", "AXTitle", "AXDescription", "AXValue",
	"AXFocused", "AXSelected", "AXEnabled", "AXRoleDescription",
] {
	var value: CFTypeRef?
	let attribute = AXUIElementCopyAttributeValue(element, name as CFString, &value)
	if attribute == .success, let value {
		print("\(name)\t\(render(value))")
	} else {
		print("\(name)\tabsent (AXError \(attribute.rawValue))")
	}
}
SWIFT

ax_out=$(swift "$work/focus.swift" "${front_pid:-0}" 2>&1)

echo
echo "== the grant, which is what picks the route"
trusted=$(printf '%s\n' "$ax_out" | awk -F'\t' '$1=="trusted" {print $2}')
say "AXIsProcessTrusted (this process)" "${trusted:-unknown}"
if [[ "$trusted" == "yes" ]]; then
	echo "   -> a bridge running here would answer getFocusInfo from the TREE."
else
	echo "   -> a bridge running here would answer getFocusInfo from the VOICEOVER"
	echo "      CURSOR, and would NOT ask for the grant to do better. Neither does"
	echo "      this script."
fi

echo
echo "== route A: the accessibility tree (what getFocusInfo answers WITH the grant)"
printf '%s\n' "$ax_out" | while IFS=$'\t' read -r key value; do
	case "$key" in
	trusted | systemwide) ;;
	AXRoleDescription) say "$key (LOCALIZED -- never used)" "$value" ;;
	*) say "$key" "$value" ;;
	esac
done

echo
echo "== the control: the system-wide element (EXPECTED TO FAIL)"
systemwide=$(printf '%s\n' "$ax_out" | awk -F'\t' '$1=="systemwide" {print $2}')
say "AXUIElementCreateSystemWide focus" "AXError ${systemwide:-unknown}"
if [[ "$systemwide" == "-25204" ]]; then
	echo "   -> -25204 kAXErrorCannotComplete, as measured. NOT a permission error"
	echo "      (-25211 is), so no grant fixes it. This is why the bridge addresses"
	echo "      AXUIElementCreateApplication(pid) instead."
elif [[ "$systemwide" == "0" ]]; then
	echo "   -> IT WORKED, which spec 0047 says it does not. That is a finding:"
	echo "      re-measure before changing the adapter, and record the macOS build."
fi

echo
echo "== route B: VoiceOver's cursors (what getFocusInfo answers WITHOUT the grant)"
vo() { osascript -e "tell application \"VoiceOver\" to $1" 2>&1 | head -1; }
say "text under cursor of vo cursor" "$(vo 'return text under cursor of vo cursor')"
# THE THIRD VIEW, and the reason it is here: the dictionary exposes a `vo cursor`
# and a separate `keyboard cursor`, spec 0046 settles that getFocusInfo means the
# keyboard/accessibility one, and nobody has measured how far apart they get.
# 13.11's guidance has to tell an agent which to reach for.
say "text under cursor of keyboard cursor" "$(vo 'return text under cursor of keyboard cursor')"

echo
echo "== reading this"
echo "   the tree column and the cursor columns AGREE"
echo "       -> the ordinary case. Both routes answer the same focus."
echo "   they DISAGREE"
echo "       -> that is the finding this script exists to make visible. The VO"
echo "          cursor is where the READER is; the tree is where the KEYBOARD is,"
echo "          and VoiceOver's cursor moves independently of focus. An agent that"
echo "          wants what the user HEARS uses"
echo "          pressGesture [\"describe item in voiceover cursor\"] and reads the"
echo "          captured speech; getFocusInfo means the keyboard view."
echo "   everything is empty or 'missing value'"
echo "       -> check the frontmost application FIRST. VoiceOver frontmost"
echo "          publishes no tree at all, and a wedged application answers the same"
echo "          way with a perfectly healthy reader (spec 0047, finding 5;"
echo "          measured again 2026-08-30 with an unresponsive Finder)."
echo "   the tree says kAXErrorNoValue (-25212) and both cursors say"
echo "   'missing value'"
echo "       -> a consistent, HEALTHY empty. Measured 2026-08-30 with TextEdit"
echo "          frontmost and no document open: nothing holds focus, so there is"
echo "          nothing to read and every column says so. This is the shape that"
echo "          looks like a dead reader and is not one."
echo "   the tree column is empty and the grant says no"
echo "       -> expected, and not a fault: that is the thin answer, which is the"
echo "          one the bridge gives rather than asking a human for a permission"
echo "          it was not told to want."
