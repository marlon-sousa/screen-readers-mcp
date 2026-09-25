// ROLE: adapter that implements UtteranceSink by appending JSON lines to a file in the extension's container.
// On macOS 15 a speech provider holding `com.apple.security.network.client` is registered but never asked
// for its voices (it logs "Skipping network entitled extension"), so a file is the only way out.
// The appends land at ~/Library/Containers/<extension bundle id>/Data/<name>.jsonl, mode 644, and an
// unsandboxed process reads them with no entitlement and no App Group.
// Writes run on a serial queue: the caller must start synthesis promptly, and the lines must keep their order.
// A failed write is logged, never thrown: throwing would fault an extension running inside VoiceOver.

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
