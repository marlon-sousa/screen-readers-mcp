// What does the accessibility API say is focused? The bridge's own two calls, as a tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
//     swift scripts/voiceover_ax_focus.swift [pid]
//
// ROLE: the AX half of two instruments -- `voiceover_focus.sh`, which shows what
// each of `getFocusInfo`'s routes answers, and `voiceover_cursors.sh`, which
// measures how far the two VoiceOver cursors get from keyboard focus. It is ONE
// file because they must measure the same thing: two copies of this program is
// one drift away from two answers about one machine.
//
// It is spec 0047's finding 8 as a re-runnable tool, and it is the prototype of
// `AXAccessibilityTree` -- the same two calls, in the same order, on the same
// API. An instrument that measured a DIFFERENT API would be evidence about
// something else.
//
// IT ASKS NOBODY ANYTHING. `AXIsProcessTrusted` shows no dialog;
// `AXIsProcessTrustedWithOptions` with the prompt option raises a system consent
// dialog and leaves the caller granted with no undo, and is deliberately not
// used. The bridge requests that grant from exactly one place -- a `typeText` --
// and an instrument that requested it would make the claim untrue for whoever
// ran the instrument.
//
// IT WRITES NOTHING. Every call here copies an attribute value out. Nothing is
// set, nothing is pressed, and no element is actioned.
//
// THE SYSTEM-WIDE READ IS A CONTROL THAT IS EXPECTED TO FAIL, kept for the same
// reason `voiceover_channels.sh` keeps its application-target probe: a
// measurement that fails on a healthy machine, so nobody rediscovers it as a
// fault. `AXUIElementCreateSystemWide()` is the obvious way to ask "what is
// focused anywhere" and answers -25204 `kAXErrorCannotComplete` -- which is NOT
// `kAXErrorAPIDisabled` (-25211), so no permission fixes it.
//
// OUTPUT IS TAB-SEPARATED `key<TAB>value` LINES, so a shell can read one field
// without parsing prose.

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

print("trusted\t\(AXIsProcessTrusted() ? "yes" : "no")")

var wide: CFTypeRef?
let wideStatus = AXUIElementCopyAttributeValue(
	AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &wide)
print("systemwide\t\(wideStatus.rawValue)")

guard CommandLine.arguments.count > 1, let pid = Int32(CommandLine.arguments[1]), pid > 0 else {
	print("focused\tno pid given")
	exit(0)
}
var focused: CFTypeRef?
let status = AXUIElementCopyAttributeValue(
	AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &focused)
guard status == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
	// -25212 is kAXErrorNoValue: nothing is focused there. AN ANSWER, not a
	// fault -- see spec 0047's finding 5, and the bridge's own inspector, which
	// reports it as an empty snapshot rather than as a reader fault.
	let named =
		status.rawValue == -25212
		? "nothing focused (kAXErrorNoValue -25212)" : "nothing (AXError \(status.rawValue))"
	print("focused\t\(named)")
	exit(0)
}
print("focused\tyes")
let element = unsafeBitCast(focused, to: AXUIElement.self)
// The list the bridge asks for, plus AXSubrole for interest -- and
// AXRoleDescription, which the bridge deliberately NEVER asks for: it is AXRole
// rendered into the user's language, and on a Portuguese machine it is what
// would silently make `role` mean something different here than elsewhere. It is
// printed so that difference is visible rather than asserted.
for name in [
	"AXRole", "AXSubrole", "AXTitle", "AXDescription", "AXValue",
	"AXFocused", "AXSelected", "AXEnabled", "AXRoleDescription",
] {
	var value: CFTypeRef?
	let attribute = AXUIElementCopyAttributeValue(element, name as CFString, &value)
	if attribute == .success, let value {
		// One line each, and newlines inside a value would break that -- a text
		// area's AXValue is the whole document.
		print("\(name)\t\(render(value).replacingOccurrences(of: "\n", with: "\\n"))")
	} else {
		print("\(name)\tabsent (AXError \(attribute.rawValue))")
	}
}
