// ROLE: adapter seam that runs a command-line tool and hands back what it said.
// IMPLEMENTED BY: SubprocessRunner and FakeProcessRunner.
// USED BY: PluginKitProviderLifecycle and SpeakSelectionVoiceStore.

import Foundation

public struct ProcessResult: Equatable, Sendable {
	public let status: Int32
	public let standardOutput: Data
	public let standardError: String

	public init(status: Int32, standardOutput: Data, standardError: String = "") {
		self.status = status
		self.standardOutput = standardOutput
		self.standardError = standardError
	}

	public var output: String {
		String(data: standardOutput, encoding: .utf8) ?? ""
	}

	public var succeeded: Bool { status == 0 }
}

/// A tool that could not be run at all, which callers treat differently from one that ran and failed.
public struct ProcessFailure: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol ProcessRunner: AnyObject {
	func run(_ executable: String, _ arguments: [String], stdin: Data?) throws -> ProcessResult
}

public extension ProcessRunner {
	func run(_ executable: String, _ arguments: [String]) throws -> ProcessResult {
		try run(executable, arguments, stdin: nil)
	}
}
