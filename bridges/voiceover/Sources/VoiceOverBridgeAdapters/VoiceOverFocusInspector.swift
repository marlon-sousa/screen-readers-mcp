// ROLE: adapter -- IMPLEMENTS the FocusInspector domain port, over two adapter
// seams: AccessibilityTree and FrontmostApplication, plus AccessibilityTrust to
// say whether the first can be asked at all.
//
// BUILT BY: VoiceOverAdapterFactory. USED BY: the GetFocusInfo handler, through
// the port.
//
// IT HOLDS EVERY DECISION ON THIS EDGE, which is what makes both of focus's
// routes ordinary unit tests with no reader present: which route answers, which
// attributes are asked for, how they become a snapshot, what a cursor read of
// `missing value` means, and what is an error at all. Below it, one leaf copies
// attribute values and another reads NSWorkspace; neither decides anything.
//
// ============================================================================
// ONE ROUTE SINCE 13.31. IT HAD A SECOND, AND THE SECOND STOPPED BEING REACHABLE.
// ============================================================================
//
// `name`, `role`, `states` and `value` come from the accessibility tree of the
// frontmost application; `appModule` comes from NSWorkspace, which costs nothing.
//
// THE FALLBACK THAT WENT: without the Accessibility grant, `name` used to come
// from VoiceOver's own cursor over an AppleEvent and the rest stayed empty. It was
// there for a session that had no Accessibility grant -- and since 13.31 there is
// no such session, because pressing keys is the only way this bridge drives the
// reader and rung 1 refuses a machine that will not allow it (spec 0055). A branch
// no session can enter is deleted rather than kept as reassurance.
//
// THE GRANT IS STILL READ HERE, AND NEVER REQUESTED. That is not vestigial: a
// human can revoke Accessibility while a session is open, and what must happen
// then is a failure that NAMES THE GRANT rather than an empty snapshot that reads
// as "nothing is focused". `AccessibilityTrust.isTrusted()` shows no dialog and
// adds this process to no list, which is exactly why focus reads the seam and not
// the domain port -- a port could go on to ask a human, and reading where you are
// must never raise a consent dialog.
//
// AND THE TWO VIEWS REALLY DO SEPARATE -- MEASURED 2026-08-30, macOS 15.0
// (24A335), rather than assumed. With a TextEdit document focused, one press of
// VoiceOver's own `stop interacting with item`:
//
// | View | Before | After one press |
// |---|---|---|
// | tree `AXRole` / `AXFocused` | `AXTextArea` / true | `AXTextArea` / true |
// | `text under cursor of vo cursor` | `alpha one` | `área de rolagem` |
// | `text under cursor of keyboard cursor` | `alpha one` | `alpha one` |
//
// So the accessibility tree tracks the KEYBOARD cursor, which is what makes it
// the right source for a command whose name is `getFocusInfo` -- and the VO
// cursor is somewhere else entirely after one ordinary keystroke. `bash
// scripts/voiceover_cursors.sh` is the re-runnable instrument.
//
// THE SAME RUN FOUND A SECOND REASON TO PREFER THE TREE, AND IT IS THE STRONGER
// ONE: the cursor route's answer is LOCALIZED. `área de rolagem` is a role
// rendered in the machine's own language, where the tree answers `AXTextArea` on
// every machine on earth. So the cursor route's `name` is not comparable across
// machines and the tree route's `role` is -- which is the lane's
// no-reader-strings rule arriving from a direction nobody was looking in. It is
// not a reason to withhold the fallback: a name a human can read is worth more
// than nothing when the grant is absent. It IS a reason no check may compare it.
//
// THERE WAS NO FALLBACK BETWEEN THE ROUTES EVEN WHEN THERE WERE TWO, and the
// reason is why the measurement above is kept: a tree route that found nothing
// focused answered EMPTY rather than quietly asking the cursor, because the two
// are different views and an answer that silently came from the other one is an
// answer an agent cannot interpret. With one route left the rule is trivially
// satisfied, and it is written down so that a future second route does not arrive
// as a silent fallback.
//
// ============================================================================
// AN EMPTY ANSWER IS NOT A FAULT, AND ON THIS READER THAT IS A RULE.
// ============================================================================
//
// Spec 0047's finding 5: VoiceOver publishes no accessibility tree of its own,
// so with VoiceOver itself frontmost every read returns `missing value` and it
// looks exactly like a dead reader. It is not one -- and the same shape arrives
// from an application that has wedged (measured 2026-08-30: an unresponsive
// Finder, with VoiceOver entirely healthy and saying so out loud). NOTHING HERE
// MAY REPORT A READER FAULT FOR AN EMPTY READ. What throws is a channel that
// refused the question: the Accessibility grant revoked, or the accessibility API
// refusing outright.
//
// AND NO STRING THE READER RENDERS IS EVER COMPARED. `AXRole` is a framework
// constant -- `AXButton` on every machine -- while `AXRoleDescription` is the
// localized rendering of it and would make `role` mean something different on
// the maintainer's Portuguese machine than on an English one. The states below
// are derived from BOOLEAN attributes for the same reason. Since 13.31 there is no
// literal matched here at all: the one that used to be, `missing value`, belonged
// to the deleted cursor route and was AppleScript's own null token rather than any
// text the reader wrote.

import VoiceOverBridgeDomain

public final class VoiceOverFocusInspector: FocusInspector {
	/// What is asked of the focused element, and the order the answers are
	/// preferred in below. Static, so the query itself is a unit test rather than
	/// something only a live machine could show you.
	///
	/// `AXTitle` before `AXDescription` because a control that has both means the
	/// title; `AXValue` is separate because the wire keeps it separate. Nothing
	/// asks for `AXRoleDescription` -- see the header.
	static let attributes = [
		"AXRole", "AXTitle", "AXDescription", "AXValue", "AXFocused", "AXSelected", "AXEnabled",
	]

	/// Boolean attributes that become `states`, in the order they are reported.
	///
	/// EACH ENTRY SAYS WHICH VALUE IS WORTH REPORTING: `AXEnabled` is interesting
	/// when it is FALSE, and the other two when they are true. A state is emitted
	/// only when the attribute is present and matches, so an element that does not
	/// carry the attribute at all contributes nothing -- "not selected" and "has
	/// no notion of selection" are different, and only the first is worth a word.
	static let stateFlags: [(attribute: String, reportedWhen: Bool, state: String)] = [
		("AXFocused", true, "focused"),
		("AXSelected", true, "selected"),
		("AXEnabled", false, "disabled"),
	]

	private let tree: any AccessibilityTree
	private let frontmost: any FrontmostApplication
	private let trust: any AccessibilityTrust

	public init(
		tree: any AccessibilityTree,
		frontmost: any FrontmostApplication,
		trust: any AccessibilityTrust
	) {
		self.tree = tree
		self.frontmost = frontmost
		self.trust = trust
	}

	public func focusInfo() throws -> FocusSnapshot {
		// ASKED FIRST, because it costs no permission and it is the one field this
		// answer can carry even when there is nothing focused at all.
		let application = frontmost.frontmostApplication()
		let appModule = application?.bundleIdentifier

		// THE GRANT IS THE ONLY THING THAT CAN TAKE THIS ROUTE AWAY, and it is a
		// FAILURE rather than an empty answer -- see the header. A session cannot
		// begin without it, so seeing it here means a human revoked it mid-session,
		// and an agent told "nothing is focused" would go looking for a defect in the
		// application instead of asking for its grant back.
		guard trust.isTrusted() else {
			throw FocusError(
				"the focus cannot be read: \(Permission.accessibility.described) Every session of "
				+ "this bridge holds that grant at the handshake, so it has been revoked since this "
				+ "one began.")
		}
		// NOTHING FRONTMOST IS AN ANSWER, not a fault: it is what a machine between
		// applications looks like, and the empty snapshot says so honestly.
		guard let application else { return FocusSnapshot(appModule: appModule) }
		return try treeSnapshot(application, appModule: appModule)
	}

	// -- the accessibility route ------------------------------------------------

	private func treeSnapshot(
		_ application: ApplicationIdentity, appModule: String?
	) throws -> FocusSnapshot {
		let element: [String: AccessibilityValue]?
		do {
			element = try tree.focusedElement(
				pid: application.processIdentifier, attributes: Self.attributes)
		} catch let failure as AccessibilityTreeFailure {
			throw FocusError(
				"the accessibility API would not answer (\(failure.code)): \(failure.description)")
		}
		// NOTHING FOCUSED IS AN ANSWER. See the header: this is what VoiceOver's
		// own process, an application between windows and a wedged one all look
		// like, and none of them is a fault of the reader's.
		guard let element else { return FocusSnapshot(appModule: appModule) }

		return FocusSnapshot(
			name: Self.name(from: element),
			role: Self.text(element["AXRole"]) ?? "",
			states: Self.states(from: element),
			value: Self.rendered(element["AXValue"]),
			appModule: appModule
		)
	}

	/// `AXTitle`, else `AXDescription`, else nothing. An element with neither has
	/// no name, which is an answer -- an unlabelled control is exactly what an
	/// agent testing accessibility is looking for.
	static func name(from element: [String: AccessibilityValue]) -> String {
		text(element["AXTitle"]) ?? text(element["AXDescription"]) ?? ""
	}

	static func states(from element: [String: AccessibilityValue]) -> [String] {
		stateFlags.compactMap { flag in
			guard case .flag(let value)? = element[flag.attribute] else { return nil }
			return value == flag.reportedWhen ? flag.state : nil
		}
	}

	/// The text of an attribute that is text, and nothing else. A flag or a
	/// number is not a name or a role, and coercing one into a string here would
	/// invent a reading the element never gave.
	static func text(_ value: AccessibilityValue?) -> String? {
		guard case .text(let text)? = value else { return nil }
		return text
	}

	/// What `value` reports, which is the one field where a non-text attribute is
	/// still worth rendering: a slider's position and a checkbox's tick are both
	/// values, and both arrive as numbers.
	///
	/// A NUMBER THAT IS A WHOLE NUMBER IS RENDERED WITHOUT ITS DECIMAL POINT, so
	/// a checkbox reads `1` rather than `1.0`. An attribute this bridge cannot
	/// render answers nil, and the wire has nowhere to say more than that -- see
	/// `AccessibilityValue.opaque`.
	static func rendered(_ value: AccessibilityValue?) -> String? {
		switch value {
		case .text(let text):
			return text
		case .flag(let flag):
			return flag ? "true" : "false"
		case .number(let number):
			return number == number.rounded() && abs(number) < 1e15
				? String(Int64(number)) : String(number)
		case .opaque, nil:
			return nil
		}
	}
}
