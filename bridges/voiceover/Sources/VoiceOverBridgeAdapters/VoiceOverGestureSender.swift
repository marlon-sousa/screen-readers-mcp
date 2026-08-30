// ROLE: adapter -- IMPLEMENTS the GestureSender domain port, over the
// AppleScriptRunner seam.
//
// BUILT BY: VoiceOverAdapterFactory. USED BY: the PressGesture handler, through
// the port.
//
// IT HOLDS EVERY DECISION ON THIS EDGE, which is what makes spec 0041's
// error-code findings ordinary unit tests: which object the command is addressed
// to, how a command name is quoted into a script, and what each error NUMBER
// means. Below it, `OSAScriptRunner` recovers a number and `SubprocessRunner`
// runs a tool; neither decides anything.
//
// ============================================================================
// THE COMMAND IS ADDRESSED TO THE **COMMANDER**, NOT TO THE APPLICATION.
// ============================================================================
//
// This one line is the finding that unblocked board entry 13.7, and it is
// written here rather than left as a detail of AppleScript style because getting
// it wrong cost two specs an argument and this entry a "measured risk" it did
// not have.
//
// `bridges/voiceover/VoiceOver.sdef` is the authority and was in the repo the
// whole time: the `application` class responds to `output`, `open`,
// `close menu` and `quit` -- and NOT to `perform command`. The `commander
// object` class responds to it, reached through the application's read-only
// `commander` property.
//
// Measured 2026-08-30, macOS 15.0 (24A335), in one sitting:
//
// | Script | Result |
// |---|---|
// | `tell application "VoiceOver" to perform command "describe item in voiceover cursor"` | **error 4** |
// | ... the same with a deliberately bogus name | **error 4** |
// | `tell application "VoiceOver" to tell commander to perform command "describe item in voiceover cursor"` | **succeeded**, and was heard aloud |
// | ... `to tell commander to perform command "no such command at all"` | **`Command does not exist (6)`** |
// | ... `to tell commander to perform command "go to desktop"` | **succeeded**; the VO cursor moved |
//
// Sending a command to an object that does not handle it fails BEFORE any name
// lookup, which is exactly why a valid name and a bogus one failed identically
// -- the detail spec 0047 recorded as the puzzle and could not explain. Spec
// 0041 measured `6` and spec 0047 measured `4` for the same call because their
// scripts differed, not because the machine changed between them.
//
// The consequence for anyone editing this file: the target is not interchangeable
// with `application "VoiceOver"`, and a "simplification" back to it would restore
// a state in which EVERY gesture fails identically and no error tells you why.

import Foundation
import VoiceOverBridgeDomain

public final class VoiceOverGestureSender: GestureSender {
	/// The AppleEvent error meaning the reader has no command by that name --
	/// `Command does not exist`. The clean failure this whole route was chosen
	/// for: it costs one round trip and changes nothing on the machine.
	static let commandDoesNotExist = 6

	/// The two errors spec 0041 measured when VoiceOver's scripting object model
	/// died without VoiceOver dying: `-1728` (no such object) and `-1708` (the
	/// event was not handled). Both mean the same thing to a caller, and both
	/// need a reader restart.
	static let objectModelDead = [-1728, -1708]

	/// The dispatcher refusing the event outright. What an application-targeted
	/// `perform command` returns for every name -- see the header.
	static let notHandledByTarget = 4

	/// The AppleEvents grant is missing: `Not authorized to send Apple events`.
	/// The one failure a first run hits, and the one whose recovery is a system
	/// setting rather than anything about this bridge.
	static let notAuthorized = -1743

	/// The reader is not running at all.
	static let applicationIsNotRunning = -600

	private let runner: any AppleScriptRunner

	public init(runner: any AppleScriptRunner) {
		self.runner = runner
	}

	public func press(_ command: String) throws {
		do {
			_ = try runner.run(Self.script(for: command))
		} catch let error as AppleScriptError {
			throw Self.gestureError(error, command)
		} catch {
			// The tool could not be run at all, which is not the reader's fault
			// and must not be reported as if it were.
			throw GestureError.failed("could not run the script: \(error)")
		}
	}

	/// The one script this adapter sends. Static and pure, so the target and the
	/// quoting are both asserted by unit tests rather than by a live reader.
	static func script(for command: String) -> String {
		"tell application \"VoiceOver\" to tell commander to perform command \"\(quoted(command))\""
	}

	/// Escape a command name for an AppleScript string literal.
	///
	/// NOT COSMETIC. A gesture id is opaque text that arrived over the wire, and
	/// it is being placed inside a quoted literal in a script that drives the
	/// user's screen reader. An unescaped quote would end the literal early and
	/// hand the rest of the id to the interpreter as code. The backslash goes
	/// first, or it would escape the backslashes this step just added.
	private static func quoted(_ command: String) -> String {
		command
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
	}

	/// What an error number means, in the domain's vocabulary.
	///
	/// Static and pure for the same reason as the script: every one of these
	/// mappings cost a live measurement to learn, and none of them should ever
	/// need one again.
	static func gestureError(_ error: AppleScriptError, _ command: String) -> GestureError {
		switch error.number {
		case commandDoesNotExist:
			return .unknownCommand(command)
		case let number where objectModelDead.contains(number):
			return .scriptingChannelDead
		case notHandledByTarget:
			// Reported with the measurement, because this is the one error whose
			// obvious reading is wrong and whose real cause is a wrong target.
			return .failed(
				"VoiceOver's commander refused the command outright (\(error.number)): "
					+ "\(error.message). Measured 2026-08-30: this is what a command addressed to the "
					+ "APPLICATION returns for every name, valid or not -- if this bridge is seeing it "
					+ "from a command addressed to the commander, the reader's scripting object model "
					+ "is not the one this adapter was written against"
			)
		case notAuthorized:
			return .failed(
				"this bridge is not allowed to send AppleEvents to VoiceOver (\(error.number)): "
					+ "\(error.message). Recovery: allow it under System Settings > Privacy & Security "
					+ "> Automation, and check that AppleScript control of VoiceOver is enabled in "
					+ "VoiceOver Utility > General"
			)
		case applicationIsNotRunning:
			return .failed(
				"VoiceOver is not running (\(error.number)): \(error.message). "
					+ "Recovery: start it with Command-F5"
			)
		default:
			return .failed("the reader refused the command '\(command)': \(error.description)")
		}
	}
}
