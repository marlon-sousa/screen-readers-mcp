// ROLE: adapter -- IMPLEMENTS the PermissionBroker domain port, and the
// AccessibilityTrust adapter seam beside it.
//
// BUILT BY: Wiring, once per process. USED BY: the TypeText and PressGesture
// handlers (`request`), ReaderEdgeSetup's first rung and the launcher's startup
// report (`status`), all through the port; and by VoiceOverFocusInspector through
// the seam.
//
// ============================================================================
// IT ANSWERED TWO PERMISSIONS BY TWO MECHANISMS. 13.31 LEFT IT ONE, AND ONE.
// ============================================================================
//
// Until this entry it also answered `automationVoiceOver` -- and it answered it by
// SENDING AN APPLEEVENT and reading the number that came back, which is why it
// held an `AppleScriptRunner` at all. That was not incidental: the grant was a
// fact about the CHANNEL rather than about this binary, because every AppleEvent
// left an `osascript` subprocess whose events macOS attributes to whatever process
// it holds responsible (measured 2026-08-30 -- the API said `-1744` about a
// machine whose reader was being driven successfully at that moment, because the
// responsible identity over SSH is `/usr/libexec/sshd-keygen-wrapper`).
//
// The command-name route is deleted (13.31, spec 0055), so this bridge sends no
// AppleEvents, so there is no channel to ask and no grant to report. What is left
// is `AXIsProcessTrusted`: an API about THIS PROCESS, which is the one that posts
// the CGEvents, so the API and the actor agree and the answer is a plain boolean.
// `AEDeterminePermissionToAutomateTarget` and the whole `AEAddressDesc` dance went
// with the case they served.
//
// AND SO IT HAS NO TEST FILE ANY MORE, WHICH IS A STATEMENT RATHER THAN A GAP.
// It decided one thing until 13.31 -- which AppleScript error numbers mean the
// automation grant is missing and which mean the question could not be answered
// -- and 13.11 moved that decision up here out of the leaf precisely so it could
// be tested. With the channel gone there is nothing left to decide: two calls into
// `ApplicationServices` and a `switch` over one case. `TCCPermissionBrokerTests`
// was deleted with it, and if you find yourself adding one back, check first
// whether you have put a decision in a leaf (root AGENTS.md, "Testing").
//
// WHAT REPLACED THE TESTED CLAIM IS A STRUCTURAL ONE: reading a permission shows
// no dialog and requesting one does, which is why `status` and `request` are
// separate methods and why `AccessibilityTrust` is a seam. A `status` call that
// raised a consent dialog would make the handshake -- which reads permissions at
// rung 1 -- into something that interrupts a blind person at their own machine,
// and what keeps that from happening is the two API calls being different, not an
// assertion.
//
// `AccessibilityTrust` IS AN ADAPTER SEAM WITH ONE METHOD, implemented here so
// that the focus inspector can READ the grant without holding a domain port that
// could also request it. Same question, different audience: a controller that
// holds the port may go on to ask a human, and an adapter that holds the seam
// cannot.
//
// The class keeps its name because what it answers is unchanged: what this
// bridge is allowed to do to the machine, and the one place it may ask for more.

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
