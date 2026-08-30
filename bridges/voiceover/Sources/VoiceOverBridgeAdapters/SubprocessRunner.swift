// ROLE: LEAF adapter -- IMPLEMENTS the ProcessRunner seam by actually launching
// the tool.
//
// USED BY: PluginKitProviderLifecycle and SpeakSelectionVoiceStore, through the
// seam, never directly.
//
// DELIBERATELY DECIDES NOTHING. It does not know what pluginkit's output means,
// what a non-zero status implies, or which tools may be run; it launches, feeds
// standard input, waits, and hands back three values. That is why it has no test
// file, per the repo's rule about leaves -- there is nothing here `Process` does
// not already guarantee. A decision that turns up in this file belongs one layer
// up.
//
// THE PIPES ARE DRAINED BEFORE THE WAIT, and that is the one thing that would be
// a bug rather than a preference: `waitUntilExit()` before reading a pipe
// deadlocks as soon as a tool writes more than the pipe buffer holds, and
// `defaults export` of a real preference domain writes far more than that -- the
// speech domain on the maintainer's machine is tens of kilobytes of base64.

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

		// Read both pipes to EOF FIRST. See the header: waiting first deadlocks on
		// any tool whose output outgrows the pipe buffer.
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
