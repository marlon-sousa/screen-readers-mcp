// ROLE: leaf adapter implementing the ProcessRunner seam by launching the tool.
// USED BY: PluginKitProviderLifecycle and SpeakSelectionVoiceStore, through the seam.

import Foundation

public final class SubprocessRunner: ProcessRunner {
	public init() {}

	public func run(_ executable: String, _ arguments: [String], stdin: Data?) throws -> ProcessResult {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = arguments

		let out = Pipe()
		let err = Pipe()
		process.standardOutput = out
		process.standardError = err
		let input = Pipe()
		process.standardInput = input

		do {
			try process.run()
		} catch {
			throw ProcessFailure("could not run \(executable): \(error)")
		}

		if let stdin {
			input.fileHandleForWriting.write(stdin)
		}
		try? input.fileHandleForWriting.close()

		// Drain both pipes before waiting: waiting first deadlocks once a tool's output outgrows the pipe buffer, which `defaults export` does.
		let stdout = out.fileHandleForReading.readDataToEndOfFile()
		let stderr = err.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()

		return ProcessResult(
			status: process.terminationStatus,
			standardOutput: stdout,
			standardError: String(data: stderr, encoding: .utf8) ?? ""
		)
	}
}
