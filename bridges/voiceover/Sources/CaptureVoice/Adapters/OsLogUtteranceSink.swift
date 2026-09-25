// ROLE: adapter that implements UtteranceSink over the unified log.
// os_log is available to a sandboxed extension even when the container file write is denied.

import Foundation
import os

public final class OsLogUtteranceSink: UtteranceSink {
	private let logger: Logger

	public init(subsystem: String, category: String) {
		self.logger = Logger(subsystem: subsystem, category: category)
	}

	public func emit(_ event: CaptureEvent) {
		let line = CaptureEventLine.json(event, at: Date().timeIntervalSince1970)
		logger.log("\(line, privacy: .public)")
	}
}
