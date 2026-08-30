// ROLE: adapter seam -- run a command-line tool and hand back what it said.
//
// NOT A DOMAIN PORT: the domain has no idea that "is the capture voice
// registered?" is answered by a subprocess at all. This is the seam between two
// adapters, which is the only way one adapter may depend on another (AGENTS.md).
//
// IMPLEMENTED BY: SubprocessRunner (a leaf: real Process, real pipes) and
// FakeProcessRunner (Tests/Fakes), which answers from a script of canned
// results.
// USED BY: PluginKitProviderLifecycle (which reads `pluginkit`) and
// SpeakSelectionVoiceStore (which reads and writes a preference domain through
// `defaults`).
//
// THIS SPLIT IS WHAT MAKES TWO ADAPTERS TESTABLE AT ALL. Both hold real
// decisions -- what pluginkit's marker column means, which plist entries may be
// rewritten, whether a write actually took -- and every one of those decisions
// would otherwise need the maintainer's own machine, in a particular state, to
// exercise. Above the seam they are ordinary unit tests; below it there is
// nothing left to test.
//
// `stdin` IS PART OF THE SEAM ON PURPOSE. `defaults import <domain> -` reads a
// whole plist from standard input, which is what lets the voice store rewrite a
// preference WITHOUT preserving it through a temporary file -- and the file was
// never the interesting part: the TYPES are (see SpeakSelectionVoiceStore).

import Foundation

/// What a tool answered.
public struct ProcessResult: Equatable, Sendable {
	public let status: Int32
	public let standardOutput: Data
	public let standardError: String

	public init(status: Int32, standardOutput: Data, standardError: String = "") {
		self.status = status
		self.standardOutput = standardOutput
		self.standardError = standardError
	}

	/// The tool's stdout as text, which is what every reader here wants.
	public var output: String {
		String(data: standardOutput, encoding: .utf8) ?? ""
	}

	public var succeeded: Bool { status == 0 }
}

/// A tool that could not be run at all -- which is different from one that ran
/// and failed, and the callers treat them differently.
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
	/// The common case: nothing on standard input.
	func run(_ executable: String, _ arguments: [String]) throws -> ProcessResult {
		try run(executable, arguments, stdin: nil)
	}
}
