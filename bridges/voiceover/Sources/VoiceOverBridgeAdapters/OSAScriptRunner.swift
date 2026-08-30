// ROLE: adapter -- IMPLEMENTS the AppleScriptRunner seam, over the ProcessRunner
// seam beneath it.
//
// BUILT BY: Wiring, once per process. USED BY: VoiceOverGestureSender and
// VoiceOverLiveness, through the seam, never directly.
//
// A LAYOUT AMENDMENT TO SPEC 0046's 13.7 TABLE, with its why. The spec names
// this file a LEAF adapter -- "~15 lines, the only untestable part of the whole
// AppleScript edge" -- and it is not one here, deliberately: it runs
// `/usr/bin/osascript` through the ProcessRunner seam that 13.6 already built,
// so the untestable part of this edge is `SubprocessRunner`, which already
// exists and is already the leaf. Reusing it means the AppleScript edge adds NO
// new untestable code at all, and the one decision this file does make -- how a
// failure's NUMBER is recovered -- becomes an ordinary unit test instead of
// something only the maintainer's machine could exercise.
//
// THE ALTERNATIVE WAS `NSAppleScript`, AND IT WAS DECLINED FOR A SECOND REASON
// BESIDES TESTABILITY: it is documented as not thread-safe, and everything here
// runs on the session's own thread rather than the main one. Every measurement
// in specs 0041 and 0047 was taken through `osascript` in any case, so this is
// also the route the findings are true of.
//
// WHAT IT DECIDES, AND IT IS EXACTLY ONE THING: turning a failed run into an
// `AppleScriptError` with a NUMBER the callers can match on. `osascript` reports
// a failure as a non-zero exit and a line on stderr shaped
// `LINE:COL: execution error: <message> (<number>)` -- measured 2026-08-30 --
// and the number is the only part of it this bridge may reason about, because
// THE MESSAGE IS LOCALIZED. On the maintainer's machine it comes back in
// Portuguese. A caller that matched on message text would pass every test
// written in English and fail on the user's machine.

import Foundation

public final class OSAScriptRunner: AppleScriptRunner {
	/// Where `osascript` lives. A constant rather than a `PATH` lookup: this is
	/// a system tool at a system path, and resolving it through the environment
	/// would let a `PATH` entry decide what runs the user's screen reader.
	static let osascriptPath = "/usr/bin/osascript"

	private let runner: any ProcessRunner

	public init(runner: any ProcessRunner) {
		self.runner = runner
	}

	public func run(_ script: String) throws -> String {
		let result = try runner.run(Self.osascriptPath, ["-e", script])
		guard result.succeeded else {
			throw Self.failure(from: result.standardError)
		}
		// Trimmed because `osascript` terminates its result with a newline, and a
		// caller comparing a reader's answer should not have to know that.
		return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// Recover the error NUMBER and a message from what `osascript` wrote.
	///
	/// Static and pure, so the parsing is testable without a subprocess. Two
	/// shapes are handled and a third is admitted:
	///
	///  * the ordinary failure, `... execution error: <message> (<number>)`;
	///  * a failure with no trailing number at all -- a tool that died, an empty
	///    stderr -- which becomes number `0` and is reported verbatim rather than
	///    classified, because guessing at an unnumbered failure is how a bridge
	///    tells an agent something confident and wrong.
	///
	/// The LAST parenthesised number is taken, not the first: the message before
	/// it is arbitrary text that may itself contain parentheses, and on this
	/// machine it is not even in English.
	static func failure(from standardError: String) -> AppleScriptError {
		let line =
			standardError
			.split(separator: "\n", omittingEmptySubsequences: true)
			.last
			.map(String.init)?
			.trimmingCharacters(in: .whitespaces) ?? ""
		guard line.hasSuffix(")"), let open = line.lastIndex(of: "(") else {
			return AppleScriptError(number: 0, message: line.isEmpty ? "the script failed" : line)
		}
		let digits = line[line.index(after: open)..<line.index(before: line.endIndex)]
		guard let number = Int(digits) else {
			return AppleScriptError(number: 0, message: line)
		}
		let message = String(line[line.startIndex..<open]).trimmingCharacters(in: .whitespaces)
		return AppleScriptError(number: number, message: strippingPrefix(message))
	}

	/// Drop `osascript`'s own `LINE:COL: execution error:` preamble, which is
	/// about the script this file wrote and means nothing to whoever reads the
	/// error. Kept if the shape is not there, rather than assumed.
	private static func strippingPrefix(_ message: String) -> String {
		guard let marker = message.range(of: "execution error: ") else { return message }
		return String(message[marker.upperBound...])
	}
}
