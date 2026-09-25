// ROLE: supporting construct, the one place this bridge requests the Accessibility grant.
// USED BY: TypeTextHandler and PressGestureHandler, before they post any event.
// DRIVES: the PermissionBroker port.
// Only a command about to post an event may request the grant; startup, the handshake and
// probes never do.

import Foundation

public enum AccessibilityGrant {
	/// Ensures this process may post system events, requesting the Accessibility grant if it is not held.
	/// `consequence` names what did not happen, and is carried in the thrown error.
	/// A request not granted at once throws as "not yet" rather than a refusal: the human answers
	/// the macOS dialog after this call returns.
	public static func ensure(_ broker: any PermissionBroker, orElse consequence: String) throws {
		guard broker.status(of: .accessibility) != .granted else { return }
		guard broker.request(.accessibility) != .granted else { return }
		throw CommandError(
			"\(Permission.accessibility.described) A request has been raised on the machine, so if "
				+ "somebody is at it they may be able to grant it now; \(consequence). This bridge "
				+ "drives VoiceOver by pressing the keys a person presses, so there is no route that "
				+ "works without it"
		)
	}
}
