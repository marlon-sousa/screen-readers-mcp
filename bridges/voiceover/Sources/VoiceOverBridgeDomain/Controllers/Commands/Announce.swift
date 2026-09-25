// ROLE: controller -- `announce`: say something to the HUMAN at the reader.
// BUILT BY: Registry. DRIVES: the Announcer port, and the session's silence cap.

import Foundation
import ScreenReaderWire

public final class AnnounceHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let params = try request.params(as: AnnounceParams.self)
		let words = params.text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !words.isEmpty else { return AckResult() }

		guard let adapters = context.adapters else {
			throw CommandError("`announce` was called before `hello` built the reader edge")
		}
		do {
			try adapters.announcer.announce(words)
		} catch {
			throw CommandError("nothing could be said to the human at the reader: \(describe(error))")
		}
		// Recorded only after the words were spoken: the silence clock marks when the human was told.
		context.transcript.announced(words)
		context.humanHeard()
		return AckResult()
	}

	private func describe(_ error: any Error) -> String {
		String(describing: error)
	}
}
