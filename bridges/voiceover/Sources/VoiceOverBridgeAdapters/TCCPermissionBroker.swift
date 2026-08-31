// ROLE: adapter -- IMPLEMENTS the PermissionBroker domain port. It asks the
// system what this process is allowed to do, asks the READER's channel what the
// events this bridge actually sends are allowed to do, and can ask the human for
// more.
//
// BUILT BY: Wiring, once per process. USED BY: the TypeText handler, through the
// port, and the launcher's startup report, which only ever reads.
//
// IT STOPPED BEING A LEAF AT 13.11, and the reason is the repo's own rule: it
// now makes a DECISION -- which AppleScript error numbers mean "the grant is
// missing" and which mean "this cannot be determined" -- and a decision in a leaf
// belongs one layer up. So it sits above the `AppleScriptRunner` seam that
// `VoiceOverGestureSender` and `VoiceOverLiveness` already sit above, the
// untestable part stays `SubprocessRunner`, and the mapping is an ordinary unit
// test against a fake runner.
//
// ITS TEST FILE MAY NEVER CALL `request`, AND THAT IS A HARD RULE RATHER THAN A
// PREFERENCE. `request` raises a real system consent dialog on the developer's
// own machine and adds this process to a list that STAYS granted afterwards; a
// test that called it would change the machine it ran on, permanently, in exactly
// the way the entry it belongs to exists to keep deliberate. The test file beside
// this one exercises `status(.automationVoiceOver)` and nothing else, because
// that is the only method here whose answer comes from a seam a test can stand
// in for. `status(.accessibility)` reads the real `AXIsProcessTrusted` and is
// left alone for the same reason `RealClock` is.
//
// EVERYTHING ELSE STILL GETS A FAKE. `Tests/Fakes/Support/ReaderEdge.swift` hands
// every session-level test a `FakePermissionBroker`, exactly as it does for the
// provider lifecycle and for the same reason: nothing but a bridge somebody
// started deliberately builds this class.
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
// TWO PERMISSIONS, TWO MECHANISMS, AND THE SECOND ONE IS NOT AN API AT ALL.
// Accessibility is `AXIsProcessTrusted`, which answers about THIS process --
// correctly, because this process is what posts the CGEvents. Automation is
// read by USING THE CHANNEL: sending VoiceOver the same `return name` probe
// every gesture route sends, through `/usr/bin/osascript`, and reading the
// number it fails with.
//
// 13.10 USED `AEDeterminePermissionToAutomateTarget` HERE AND IT WAS WRONG, in a
// way that produced a confident false negative rather than an error. That API
// answers about the CALLING BINARY, and this bridge never sends an AppleEvent
// itself: every one leaves an `osascript` subprocess, whose events macOS
// attributes to whatever process it holds RESPONSIBLE -- the app bundle when the
// bridge runs as one, and whatever launched it when it does not.
//
// MEASURED 2026-08-30 on the maintainer's machine, seconds apart:
//
//     AEDeterminePermissionToAutomateTarget(com.apple.VoiceOver, false)  -> -1744
//     /usr/bin/osascript -e 'tell application "VoiceOver" to return name' -> "VoiceOver"
//
// -1744 is `errAEEventWouldRequireUserConsent`, which the old code reported as
// `notGranted` -- while that same process had just driven the reader through a
// whole MCP session. The grant was held by the responsible process all along
// (VS Code launched over SSH, Claude Code from VS Code, the bridge from Claude
// Code, so TCC consulted `/usr/libexec/sshd-keygen-wrapper`). An unsigned
// binary gets its own identity and so answers about nobody.
//
// `request` KEEPS THE API, and that is deliberate rather than an oversight: it
// asks on behalf of this binary's responsible process, which for the SHIPPED
// .app is exactly the identity that will send the events. Nothing calls it
// today; the control dialog's Request button (13.14) is its first caller.
//
// The class keeps its name because what it answers is unchanged: what this
// bridge is allowed to do to the machine, and the one place it may ask for more.

import ApplicationServices
import CoreServices
import Foundation
import VoiceOverBridgeDomain

public final class TCCPermissionBroker: PermissionBroker, AccessibilityTrust {
	/// Who the automation grant is about. VoiceOver's own bundle identifier, which
	/// is what macOS keys the Automation list by -- and what
	/// `VoiceOverGestureSender` is ultimately addressing when it reports `-1743`.
	static let readerBundleID = "com.apple.VoiceOver"

	private let scripts: any AppleScriptRunner

	public init(scripts: any AppleScriptRunner) {
		self.scripts = scripts
	}

	public func status(of permission: Permission) -> PermissionState {
		switch permission {
		case .accessibility:
			return isTrusted() ? .granted : .notGranted
		case .automationVoiceOver:
			return automationOverTheChannel()
		}
	}

	/// Whether the events this bridge actually sends are getting through, asked by
	/// sending one.
	///
	/// ASKING NOBODY: the probe is a read (`return name`), so a machine with the
	/// grant answers it silently and a machine without one fails it silently. No
	/// consent dialog is raised on either path, which is what keeps this safe to
	/// call at startup on an unattended machine and on every refresh of a dialog
	/// somebody left open.
	///
	/// THREE ANSWERS, AND ONLY ONE OF THEM IS AN OPINION ABOUT A PERMISSION:
	///
	///  * a reply -- the channel works, so the grant is held, whoever holds it;
	///  * `-1743` (`errAEEventNotPermitted`) -- the one number that means the
	///    grant is missing, and the same one every gesture already reports;
	///  * anything else -- the reader is not running, `osascript` could not be
	///    launched, the object model is wedged. None of those is evidence about a
	///    permission, so none of them is reported as one.
	///
	/// The number is read and the MESSAGE is not, which is `AppleScriptRunner`'s
	/// standing rule: on this machine `osascript` writes it in Portuguese.
	private func automationOverTheChannel() -> PermissionState {
		do {
			_ = try scripts.run(VoiceOverLiveness.readerNameScript)
			return .granted
		} catch let failure as AppleScriptError
			where failure.number == VoiceOverGestureSender.notAuthorized
		{
			return .notGranted
		} catch {
			return .cannotTell
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
			// NOT the same call as `status` any more, and the asymmetry is the point.
			// Reading asks the CHANNEL, because the channel is what sends the events;
			// asking asks the SYSTEM about this binary's responsible process, because
			// that is the only identity macOS can put a consent dialog against. For the
			// shipped .app those are the same identity. For a debug launcher they are
			// not -- which is why this method has no caller yet and why the launcher
			// prints `status` rather than offering to fix it.
			//
			// The answer is what stands NOW: a first request nearly always answers
			// `notGranted` because the dialog is still on the screen.
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

	/// Put the automation question to the human, on behalf of this binary's
	/// responsible process.
	///
	/// ONLY `request` USES THIS NOW. It is not a way to READ the grant -- see the
	/// header's measurement, and `automationOverTheChannel` above, which is.
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
	/// human the request. That decision, and why it is a DIFFERENT question from
	/// the `cannotTell` that 13.11 added, is recorded in `PermissionState`'s own
	/// header.
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
