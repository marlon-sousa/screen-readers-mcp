// A hand-written stateful fake for the ProcessRunner adapter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/ProcessRunner.swift.
//
// It answers from a table keyed by the FIRST argument, because both adapters
// above this seam run one tool with two different verbs -- `defaults export` and
// `defaults import` -- and a test that could not tell them apart would be
// asserting that something ran rather than that the right thing did.
//
// Every invocation is recorded whole, which is what lets a test assert the
// EXACT arguments: a wrong preference domain is invisible in an assertion about
// success, and would quietly rewrite somebody else's settings.

import Foundation

@testable import VoiceOverBridgeAdapters

public final class FakeProcessRunner: ProcessRunner {
	public struct Invocation: Equatable {
		public let executable: String
		public let arguments: [String]
		public let stdin: Data?

		/// Public since 13.20, so a test can assert the WHOLE invocation as one
		/// value rather than three separate expectations. `register()` runs two
		/// tools whose ORDER is the contract, and comparing the array of these is
		/// how that order is asserted in one line.
		public init(executable: String, arguments: [String], stdin: Data? = nil) {
			self.executable = executable
			self.arguments = arguments
			self.stdin = stdin
		}
	}

	public private(set) var invocations: [Invocation] = []
	/// Keyed by the first argument (`export`, `import`, `-m`, ...). Anything not
	/// in the table answers with a non-zero status, which is what an unknown verb
	/// does on a real machine.
	public var answers: [String: ProcessResult] = [:]
	/// When set, `run` throws instead of answering -- the tool is not there at all.
	public var failure: ProcessFailure?

	/// Called before each invocation is answered, so a test can make the machine
	/// CHANGE while something is polling it.
	///
	/// It arrived with 13.20's registration, whose whole point is that `pluginkit
	/// -a` hands its work to `pkd` and returns: the extension appears in the
	/// listing some polls later, and a fake that could only answer one thing
	/// forever could not tell a poll that waits from one that got lucky.
	public var beforeRun: ((String, [String]) -> Void)?

	public init() {}

	public func run(_ executable: String, _ arguments: [String], stdin: Data?) throws -> ProcessResult {
		beforeRun?(executable, arguments)
		invocations.append(Invocation(executable: executable, arguments: arguments, stdin: stdin))
		if let failure { throw failure }
		let verb = arguments.first ?? ""
		return answers[verb] ?? ProcessResult(status: 1, standardOutput: Data(), standardError: "no such verb")
	}

	/// The bytes handed to the last invocation with this verb, which is how a
	/// test reads what was written without a filesystem.
	public func stdin(forVerb verb: String) -> Data? {
		invocations.last { $0.arguments.first == verb }?.stdin
	}
}
