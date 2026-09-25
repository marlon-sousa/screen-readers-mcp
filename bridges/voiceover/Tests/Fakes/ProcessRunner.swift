// Hand-written stateful fake for the ProcessRunner adapter seam, answering by first argument.

import Foundation

@testable import VoiceOverBridgeAdapters

public final class FakeProcessRunner: ProcessRunner {
	public struct Invocation: Equatable {
		public let executable: String
		public let arguments: [String]
		public let stdin: Data?

		public init(executable: String, arguments: [String], stdin: Data? = nil) {
			self.executable = executable
			self.arguments = arguments
			self.stdin = stdin
		}
	}

	public private(set) var invocations: [Invocation] = []
	public var answers: [String: ProcessResult] = [:]
	public var failure: ProcessFailure?

	public var beforeRun: ((String, [String]) -> Void)?

	public init() {}

	public func run(_ executable: String, _ arguments: [String], stdin: Data?) throws -> ProcessResult {
		beforeRun?(executable, arguments)
		invocations.append(Invocation(executable: executable, arguments: arguments, stdin: stdin))
		if let failure { throw failure }
		let verb = arguments.first ?? ""
		return answers[verb] ?? ProcessResult(status: 1, standardOutput: Data(), standardError: "no such verb")
	}

	public func stdin(forVerb verb: String) -> Data? {
		invocations.last { $0.arguments.first == verb }?.stdin
	}
}
