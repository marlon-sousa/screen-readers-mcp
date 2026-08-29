// ROLE: adapter -- implements UtteranceSink over the unified log.
//
// The SECOND route, and it exists because it works where the first one may not:
// os_log is available to a sandboxed extension unconditionally, while the
// container file write can be denied. Read live with
//
//     log stream --predicate 'subsystem == "org.screen-readers-mcp.voiceover"'
//
// WHY os_log AND NOT print. A `print` is a synchronous flush to the console on
// the calling thread -- here, the thread that must promptly start synthesis
// inside the user's screen reader. os_log is asynchronous and cheap by design,
// and it is the only logging this module does: nothing in CaptureVoice prints.
//
// The message is marked `.public` because it is our own text about our own
// process, and redacted-to-`<private>` log lines are exactly what made
// VoiceOver's own log useless (spec 0046, part 2).

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
