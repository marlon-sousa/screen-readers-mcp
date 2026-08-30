// ROLE: LEAF adapter -- IMPLEMENTS the PermissionBroker domain port. It asks the
// system whether this process is trusted to synthesize input, and can ask the
// human to make it so.
//
// BUILT BY: Wiring, once per process. USED BY: the TypeText handler, through the
// port -- and from 13.10 by the dialog's permission row.
//
// NO TEST FILE, AND HERE THAT IS A HARD RULE RATHER THAN THE USUAL LEAF
// ARGUMENT. `request` raises a real system consent dialog on the developer's own
// machine and adds this process to a list that STAYS granted afterwards; a test
// that called it would change the machine it ran on, permanently, and could not
// undo it. So nothing but a bridge somebody started deliberately ever builds
// this class -- `Tests/Fakes/Support/ReaderEdge.swift` hands every test a fake,
// exactly as it does for the provider lifecycle and for the same reason.
//
// IT ANSWERS TWO INTERFACES AT TWO LAYERS, SINCE 13.9, AND THAT IS ONE LEAF
// RATHER THAN TWO. `PermissionBroker` is the DOMAIN's port -- the shape a
// controller needs, because deciding to ask a human for a grant is a decision
// about their machine. `AccessibilityTrust` is an ADAPTER SEAM with one method,
// `isTrusted`, because focus uses the same fact for something else entirely: it
// picks between the accessibility tree and the VoiceOver cursor, and a route
// choice is a decision that belongs beside the routes. Both read the same system
// Bool, so one class answering both is what keeps a single place in this bridge
// talking to the permission machinery. See `Ports/AccessibilityTrust.swift`,
// whose header carries the layout argument and the alternative it was chosen
// over.
//
// AND IT IS BUILT, BUT NOT ASKED, AT STARTUP. Constructing this object talks to
// nobody. `status` reads a Bool and shows nothing. Only `request` raises
// anything, and the ONLY call to it in this repository is in the TypeText
// handler -- which is what makes "a session that only presses commands and reads
// speech never triggers an Accessibility request" a checkable statement about
// this bridge. Nothing here may be called from Wiring, the adapter factory, the
// doctor or a probe.

import ApplicationServices
import VoiceOverBridgeDomain

public final class TCCPermissionBroker: PermissionBroker, AccessibilityTrust {
	public init() {}

	public func status(of permission: Permission) -> PermissionState {
		switch permission {
		case .accessibility:
			return isTrusted() ? .granted : .notGranted
		}
	}

	/// The AccessibilityTrust seam: the same question, asked by the adapter that
	/// acts on it rather than by a controller that would go on to request it.
	/// SHOWS NOTHING -- `AXIsProcessTrusted` takes no options and raises no
	/// dialog, which is what lets focus read it on every call.
	public func isTrusted() -> Bool {
		AXIsProcessTrusted()
	}

	public func request(_ permission: Permission) -> PermissionState {
		switch permission {
		case .accessibility:
			// The SAME call as `status`, with the one option that makes macOS put
			// the question to the human. It returns the trust as it stands NOW, so a
			// first request nearly always answers `notGranted` -- the human is being
			// sent to System Settings and has not arrived yet. The caller says "not
			// yet" rather than "refused" for exactly that reason.
			let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
			return AXIsProcessTrustedWithOptions(prompt as CFDictionary) ? .granted : .notGranted
		}
	}
}
