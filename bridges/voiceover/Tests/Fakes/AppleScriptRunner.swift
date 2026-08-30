// A hand-written stateful fake for the AppleScriptRunner adapter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/AppleScriptRunner.swift.
//
// It records every script VERBATIM, and that is what the seam is for: the target
// object a command is addressed to is a decision that lives in the script text
// and nowhere else, and it is the decision that cost this lane two specs of
// argument (see VoiceOverGestureSender). A double that only recorded "a script
// ran" could not tell the working script from the one that fails identically for
// every command.
//
// It answers from a queue rather than a table, because the two adapters above
// this seam send DIFFERENT scripts for different questions and a test usually
// cares about the sequence: dispatch fails, then liveness is asked. A queue that
// runs out answers successfully, which is the ordinary case.

import VoiceOverBridgeAdapters

public final class FakeAppleScriptRunner: AppleScriptRunner {
	/// What each successive call should do, front first. An empty queue answers
	/// with `defaultAnswer`.
	public var answers: [Result<String, any Error>] = []

	/// What a call answers once the queue is empty.
	public var defaultAnswer = ""

	public private(set) var scripts: [String] = []

	public init() {}

	/// Fail the next call with an AppleScript error NUMBER, which is the only
	/// part of a failure the adapters above may reason about -- the message is
	/// localized on a real machine.
	public func failNext(number: Int, message: String = "it did not work") {
		answers.append(.failure(AppleScriptError(number: number, message: message)))
	}

	public func succeedNext(_ output: String = "") {
		answers.append(.success(output))
	}

	public func run(_ script: String) throws -> String {
		scripts.append(script)
		guard !answers.isEmpty else { return defaultAnswer }
		return try answers.removeFirst().get()
	}
}
