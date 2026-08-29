// ROLE: adapter -- implements UtteranceSink by appending JSON lines to a file in
// the extension's own container.
//
// THIS IS THE ONLY DOOR OUT OF THE EXTENSION, and not for want of trying. A
// speech provider holding `com.apple.security.network.client` is not rejected
// with an error: macOS registers it, launches it, constructs its audio unit, and
// then never asks it for its voices, logging "Skipping network entitled
// extension" where nobody looks. So there is no socket, no port and no XPC here
// -- there is a file (spec 0041, B1 and B2).
//
// Measured: the sandboxed extension's appends land at
// ~/Library/Containers/<extension bundle id>/Data/<name>.jsonl, mode 644, owned
// by the user, and an ordinary unsandboxed process reads them with no
// entitlement and no App Group. The App Group was requested in the entitlements
// and turned out to be unnecessary for this direction.
//
// WRITES HAPPEN ON A SERIAL QUEUE, off the caller's thread. The caller is the
// thread that must promptly start synthesis inside the user's screen reader, and
// a file open/seek/write is the one blocking thing this class does. Serial, so
// the lines keep their order -- which is the whole point of the feed.
//
// A FAILED WRITE IS REPORTED, not swallowed: it is logged rather than thrown,
// because throwing out of here would fault an extension inside VoiceOver, and a
// feed that goes quiet with no explanation is the failure mode this route is
// least able to diagnose.

import Foundation
import os

public final class ContainerFileUtteranceSink: UtteranceSink {
	private let path: String
	private let logger: Logger
	private let queue: DispatchQueue

	public init(path: String, subsystem: String) {
		self.path = path
		self.logger = Logger(subsystem: subsystem, category: "capture-file")
		self.queue = DispatchQueue(label: subsystem + ".capture-file", qos: .utility)
	}

	public func emit(_ event: CaptureEvent) {
		let line = CaptureEventLine.json(event, at: Date().timeIntervalSince1970)
		queue.async { [path, logger] in
			if let failure = ContainerFileUtteranceSink.append(line, to: path) {
				logger.error(
					"capture-file-write-failed path=\(path, privacy: .public) reason=\(failure, privacy: .public)")
			}
		}
	}

	/// Returns the failure reason rather than throwing, so a sandbox denial is
	/// data instead of a crash inside the extension.
	private static func append(_ line: String, to path: String) -> String? {
		guard let data = (line + "\n").data(using: .utf8) else { return "utf8" }
		let url = URL(fileURLWithPath: path)
		do {
			if FileManager.default.fileExists(atPath: path) {
				let handle = try FileHandle(forWritingTo: url)
				defer { try? handle.close() }
				try handle.seekToEnd()
				try handle.write(contentsOf: data)
			} else {
				try data.write(to: url)
			}
			return nil
		} catch {
			return String(describing: error)
		}
	}
}
