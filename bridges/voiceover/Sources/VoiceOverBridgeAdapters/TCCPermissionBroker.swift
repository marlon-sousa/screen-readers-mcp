// ROLE: adapter implementing the PermissionBroker port and the AccessibilityTrust seam.
// BUILT BY: Wiring, once per process.
// USED BY: the TypeText and PressGesture handlers, ReaderEdgeSetup and the launcher through the port, and VoiceOverFocusInspector through the seam.
// `status` and `isTrusted` must never show a dialog, because the handshake reads them; only `request` may prompt.

import ApplicationServices
import Foundation
import VoiceOverBridgeDomain

public final class TCCPermissionBroker: PermissionBroker, AccessibilityTrust {
	public init() {}

	public func status(of permission: Permission) -> PermissionState {
		switch permission {
		case .accessibility:
			return isTrusted() ? .granted : .notGranted
		}
	}

	public func isTrusted() -> Bool {
		AXIsProcessTrusted()
	}

	public func request(_ permission: Permission) -> PermissionState {
		switch permission {
		case .accessibility:
			// Prompts the human, but returns trust as it stands now, so a first request nearly always answers `notGranted`.
			let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
			return AXIsProcessTrustedWithOptions(prompt as CFDictionary) ? .granted : .notGranted
		}
	}
}
