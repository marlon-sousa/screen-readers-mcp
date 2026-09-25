// What does the accessibility API say is focused? The bridge's own two calls, as a tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
//     swift scripts/voiceover_ax_focus.swift [pid]
// ROLE: the accessibility half of `voiceover_focus.sh` and `voiceover_cursors.sh`, making the same two
// calls as `AXAccessibilityTree`; it prints tab-separated `key<TAB>value` lines.
// It must never request the accessibility grant: `AXIsProcessTrustedWithOptions` with the prompt option
// leaves the caller granted with no undo.
// The system-wide read is a control expected to fail: it answers -25204 kAXErrorCannotComplete, not
// -25211 kAXErrorAPIDisabled, so no permission fixes it.

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
	// -25212 is kAXErrorNoValue: nothing is focused there, which is an answer, not a fault.
	let named =
		status.rawValue == -25212
		? "nothing focused (kAXErrorNoValue -25212)" : "nothing (AXError \(status.rawValue))"
	print("focused\t\(named)")
	exit(0)
}
print("focused\tyes")
let element = unsafeBitCast(focused, to: AXUIElement.self)
// The bridge's list plus AXSubrole and AXRoleDescription, which the bridge never asks for because it is
// localised.
for name in [
	"AXRole", "AXSubrole", "AXTitle", "AXDescription", "AXValue",
	"AXFocused", "AXSelected", "AXEnabled", "AXRoleDescription",
] {
	var value: CFTypeRef?
	let attribute = AXUIElementCopyAttributeValue(element, name as CFString, &value)
	if attribute == .success, let value {
		// A text area's AXValue is the whole document, newlines included.
		print("\(name)\t\(render(value).replacingOccurrences(of: "\n", with: "\\n"))")
	} else {
		print("\(name)\tabsent (AXError \(attribute.rawValue))")
	}
}
