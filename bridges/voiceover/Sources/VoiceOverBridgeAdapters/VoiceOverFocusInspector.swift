// ROLE: adapter -- IMPLEMENTS the FocusInspector domain port, over three adapter
// seams: AccessibilityTree, AppleScriptRunner and FrontmostApplication, plus
// AccessibilityTrust to choose between the first two.
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
// TWO ROUTES, CHOSEN BY A PERMISSION THIS BRIDGE NEVER ASKS FOR.
// ============================================================================
//
// With the Accessibility grant held: `name`, `role`, `states` and `value` come
// from the accessibility tree of the frontmost application. Without it: `name`
// comes from VoiceOver's own cursor over AppleEvents, and the rest is empty.
// `appModule` is answered from NSWorkspace on both, because it costs nothing on
// either.
//
// THE GRANT IS READ, NEVER REQUESTED. `AccessibilityTrust.isTrusted()` shows no
// dialog and adds this process to no list; every call to
// `PermissionBroker.request` in this repository is in a command handler that is
// about to post a system event -- a `typeText`, or a keystroke `pressGesture` --
// and 13.8's lever is that reading focus never joins them. So focus is RICHER on a
// machine where typing has already been granted and works everywhere else --
// which is the honest shape for a capability that cannot pay for itself.
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
// THERE IS NO FALLBACK BETWEEN THE ROUTES, deliberately. A tree route that finds
// nothing focused answers EMPTY rather than quietly asking the cursor: the two
// are different views (spec 0046, "The two cursors, settled"), and an answer
// that silently came from the other one is an answer an agent cannot interpret.
// The grant picks the route; the route answers.
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
// refused the question: the AppleEvents grant missing, the reader not running,
// the accessibility API refusing outright.
//
// AND NO STRING THE READER RENDERS IS EVER COMPARED. `AXRole` is a framework
// constant -- `AXButton` on every machine -- while `AXRoleDescription` is the
// localized rendering of it and would make `role` mean something different on
// the maintainer's Portuguese machine than on an English one. The states below
// are derived from BOOLEAN attributes for the same reason. `missing value` is
// the one literal matched here and it is AppleScript's own token, not the
// reader's text.

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

	/// The cursor route's one script. Static and pure, so the text that would
	/// reach `osascript` is asserted by a unit test -- the same guarantee
	/// `VoiceOverGestureSender.script(for:)` gives the gesture edge.
	///
	/// THE VO CURSOR, NOT THE KEYBOARD CURSOR. VoiceOver's dictionary exposes
	/// both, each with its own `text under cursor`, and they are two views that
	/// only usually agree. `getFocusInfo` means the keyboard/accessibility view
	/// (spec 0046, "The two cursors, settled"), and the VO cursor is what remains
	/// readable when the accessibility route is shut -- so this is the fallback,
	/// stated as one. An agent that wants what the USER HEARS asks for
	/// `pressGesture ["describe item in voiceover cursor"]` and reads the speech.
	static let cursorScript =
		"tell application \"VoiceOver\" to return text under cursor of vo cursor"

	/// AppleScript's own token for "there is nothing there". NOT a reader string:
	/// it is the language's null literal as `osascript` prints it, which is why
	/// matching it is allowed where matching a rendered name would not be.
	static let missingValue = "missing value"

	private let tree: any AccessibilityTree
	private let scripts: any AppleScriptRunner
	private let frontmost: any FrontmostApplication
	private let trust: any AccessibilityTrust

	public init(
		tree: any AccessibilityTree,
		scripts: any AppleScriptRunner,
		frontmost: any FrontmostApplication,
		trust: any AccessibilityTrust
	) {
		self.tree = tree
		self.scripts = scripts
		self.frontmost = frontmost
		self.trust = trust
	}

	public func focusInfo() throws -> FocusSnapshot {
		// ASKED FIRST AND ON BOTH ROUTES, because it costs no permission and it is
		// the only field either route can always fill in.
		let application = frontmost.frontmostApplication()
		let appModule = application?.bundleIdentifier

		guard trust.isTrusted(), let application else {
			return try cursorSnapshot(appModule: appModule)
		}
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

	// -- the VoiceOver cursor route ---------------------------------------------

	private func cursorSnapshot(appModule: String?) throws -> FocusSnapshot {
		let text: String
		do {
			text = try scripts.run(Self.cursorScript)
		} catch let failure as AppleScriptError {
			throw FocusError(Self.explain(failure))
		} catch {
			throw FocusError("could not run the script: \(error)")
		}
		// `missing value` IS EMPTY, NOT AN ERROR -- spec 0047's finding 5, which is
		// the whole reason this line is a mapping rather than a `throw`.
		let name = text == Self.missingValue ? "" : text
		// `role`, `states` and `value` stay empty: the cursor answers with a
		// rendering, not with structure, and inventing a role from it would be a
		// guess an agent could not tell from a reading.
		return FocusSnapshot(name: name, appModule: appModule)
	}

	/// What an AppleScript failure means to an agent asking where it is.
	///
	/// IT REUSES THE NUMBERS `VoiceOverGestureSender` DECLARES rather than
	/// copying them: they cost live measurements to learn, and two adapters with
	/// their own copies is one drift away from two bridges disagreeing about the
	/// same machine. The messages are local because the recoveries are -- nothing
	/// was pressed here, so there is nothing to say about a command.
	static func explain(_ failure: AppleScriptError) -> String {
		switch failure.number {
		case VoiceOverGestureSender.notAuthorized:
			return
				"this bridge is not allowed to send AppleEvents to VoiceOver (\(failure.number)): "
				+ "\(failure.message). Recovery: allow it under System Settings > Privacy & Security "
				+ "> Automation, and check that AppleScript control of VoiceOver is enabled in "
				+ "VoiceOver Utility > General. Granting Accessibility instead would let this bridge "
				+ "read the focus from the accessibility tree, which is the richer answer"
		case VoiceOverGestureSender.applicationIsNotRunning:
			return
				"VoiceOver is not running (\(failure.number)): \(failure.message). "
				+ "Recovery: start it with Command-F5"
		case let number where VoiceOverGestureSender.objectModelDead.contains(number):
			return "the focus could not be read from the VoiceOver cursor. "
				+ ReaderCondition.scriptingChannelDead.described
		default:
			return "the focus could not be read from the VoiceOver cursor: \(failure.description)"
		}
	}
}
