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
// AND IT IS BUILT, BUT NOT ASKED, AT STARTUP. Constructing this object talks to
// nobody. `status` reads a Bool and shows nothing. Only `request` raises
// anything, and the ONLY call to it in this repository is in the TypeText
// handler -- which is what makes "a session that only presses commands and reads
// speech never triggers an Accessibility request" a checkable statement about
// this bridge. Nothing here may be called from Wiring, the adapter factory, the
// doctor or a probe.

import ApplicationServices
import VoiceOverBridgeDomain

public final class TCCPermissionBroker: PermissionBroker {
	public init() {}

	public func status(of permission: Permission) -> PermissionState {
		switch permission {
		case .accessibility:
			return AXIsProcessTrusted() ? .granted : .notGranted
		}
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
