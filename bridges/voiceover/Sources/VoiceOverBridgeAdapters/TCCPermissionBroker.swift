// ROLE: LEAF adapter -- IMPLEMENTS the PermissionBroker domain port. It asks the
// system what this process is allowed to do, and can ask the human for more.
//
// BUILT BY: Wiring, once per process. USED BY: the TypeText handler, through the
// port, and the launcher's startup report, which only ever reads.
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
// nobody. `status` reads and shows nothing -- deliberately, on BOTH permissions:
// the automation question is asked with `askUserIfNeeded: false`, which is the
// difference between drawing a row and raising a consent dialog on a machine
// nobody is sitting at.
//
// ONLY `request` RAISES ANYTHING, AND THE ONLY CALL TO IT IN THIS REPOSITORY IS
// IN THE TYPETEXT HANDLER -- which is what makes "a session that only presses
// commands and reads speech never triggers an Accessibility request" a checkable
// statement about this bridge. Nothing here may be called from Wiring, the
// adapter factory, the doctor or a probe. The counting-broker scenario in
// `Tests/Integration/SessionRoundTripTests.swift` is where it is asserted.
//
// TWO PERMISSIONS, TWO SYSTEM APIS, AND THE SECOND ONE IS NOT A TCC BOOL.
// Accessibility is `AXIsProcessTrusted`; automation is per TARGET, so it is
// `AEDeterminePermissionToAutomateTarget` addressed at VoiceOver's bundle id.
// The class keeps its name because what it answers is unchanged: what this
// process is allowed to do, and the one place it may ask for more.

import ApplicationServices
import CoreServices
import Foundation
import VoiceOverBridgeDomain

public final class TCCPermissionBroker: PermissionBroker, AccessibilityTrust {
	/// Who the automation grant is about. VoiceOver's own bundle identifier, which
	/// is what macOS keys the Automation list by -- and what
	/// `VoiceOverGestureSender` is ultimately addressing when it reports `-1743`.
	static let readerBundleID = "com.apple.VoiceOver"

	public init() {}

	public func status(of permission: Permission) -> PermissionState {
		switch permission {
		case .accessibility:
			return isTrusted() ? .granted : .notGranted
		case .automationVoiceOver:
			// ASKING NOBODY: `askUserIfNeeded: false` is what makes this safe to call
			// on every refresh of a dialog that may be open on an unattended machine.
			return automation(askUserIfNeeded: false)
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
		case .automationVoiceOver:
			// The same call as `status`, with the flag that makes macOS put the
			// question to the human. Like the Accessibility path below, the answer is
			// what stands NOW: a first request nearly always answers `notGranted`
			// because the dialog is still on the screen.
			return automation(askUserIfNeeded: true)
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

	/// Whether this process may send AppleEvents to the reader.
	///
	/// ADDRESSED BY BUNDLE ID rather than by process id, so the answer is the same
	/// whether or not VoiceOver happens to be running -- which matters, because a
	/// dialog drawn while the reader is off would otherwise report a permission
	/// problem where there is none.
	///
	/// THREE ANSWERS COLLAPSED INTO TWO, on purpose: the API distinguishes "not
	/// yet asked" (`errAEEventWouldRequireUserConsent`) from "refused"
	/// (`errAEEventNotPermitted`), and `PermissionState` reports both as
	/// `notGranted` because what a caller does about them is identical -- offer the
	/// human the request. That decision, and why a third state was declined, is
	/// recorded in `PermissionState`'s own header.
	private func automation(askUserIfNeeded: Bool) -> PermissionState {
		var target = AEAddressDesc()
		var identifier = Array(TCCPermissionBroker.readerBundleID.utf8)
		guard AECreateDesc(typeApplicationBundleID, &identifier, identifier.count, &target) == noErr
		else {
			return .notGranted
		}
		defer { AEDisposeDesc(&target) }
		let answer = AEDeterminePermissionToAutomateTarget(
			&target, typeWildCard, typeWildCard, askUserIfNeeded)
		return answer == noErr ? .granted : .notGranted
	}
}
