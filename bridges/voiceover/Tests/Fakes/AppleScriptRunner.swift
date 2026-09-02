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

	/// Answers keyed by the EXACT script text, consulted after the queue and
	/// before `defaultAnswer`.
	///
	/// IT ARRIVED WITH 13.20, BECAUSE THE HANDSHAKE NOW SENDS TWO DIFFERENT
	/// SCRIPTS DOWN ONE RUNNER. Until then a test drove one adapter at a time and
	/// a single `defaultAnswer` was enough; now `ReaderEdgeSetup` asks the reader
	/// its own name AND presses a command, through the same seam, and a fake that
	/// answered both the same way would either report a dead reader on every
	/// healthy machine or put the reader's name into every gesture's reply. This
	/// is `FakeProcessRunner`'s table keyed by verb, in the form this seam allows.
	public var scriptedAnswers: [String: String] = [:]

	public private(set) var scripts: [String] = []

	/// Called with each script before it is answered, so scaffolding can make a
	/// script have a CONSEQUENCE -- the way `FakeGestureSender.onPress` does.
	///
	/// It exists for 13.20's capture proof: the handshake presses a command and
	/// requires an utterance to come back, so a fake reader that never says
	/// anything is a fake machine that cannot be connected to. The IO that makes
	/// that happen lives in `Support/ReaderEdge.swift`, never here -- a port
	/// double that wrote files would be a double doing the thing doubles exist to
	/// avoid.
	public var onScript: ((String) -> Void)?

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
		onScript?(script)
		guard !answers.isEmpty else { return scriptedAnswers[script] ?? defaultAnswer }
		return try answers.removeFirst().get()
	}
}
