// ROLE: controller for `typeText`: inserts literal text where the focus is, then reports what the
// reader said.
// BUILT BY: Registry. DRIVES: the PermissionBroker and TextTyper ports and the session's
// SpeechBuffer.
// The grant is checked before the injection, which cannot fail visibly; see TextTyper.

import Foundation
import ScreenReaderWire

public final class TypeTextHandler: CommandHandler {
	public let mutatesReader = true

	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let params = try request.params(as: TypeParams.self)
		let adapters = try readerEdge(context)
		let buffer = try context.speechBuffer()
		let grace = Double(max(0, params.graceMs)) / 1000.0

		// Warned before the grant is asked for and before anything is typed.
		try HumanWarning.honour(context, params.announce)

		try AccessibilityGrant.ensure(adapters.permissions, orElse: "nothing was typed")

		let startIndex = buffer.nextIndex()
		// Recorded before the injection, so a failed attempt is still in the record: the length, never
		// the text.
		context.transcript.typed(Self.count(params.text))
		do {
			try adapters.textTyper.type(params.text)
		} catch let failure as TypingError {
			throw CommandError("the text could not be typed: \(failure.description)")
		}
		let read = buffer.collectSince(startIndex, grace: grace)

		return TypeResult(
			// The length, never the text: this is how a secret is entered.
			typed: Self.count(params.text),
			speech: Observation.speechEntries(read.entries),
			speechFrom: read.fromIndex,
			speechTo: read.toIndex,
			// Nil: this bridge announces no `state` capability.
			state: nil
		)
	}

	/// Unicode scalars, not grapheme clusters: `typed` must match the code-point count the other wire
	/// bindings report.
	static func count(_ text: String) -> Int {
		text.unicodeScalars.count
	}

	private func readerEdge(_ context: SessionContext) throws -> AdapterSet {
		guard let adapters = context.adapters else {
			throw CommandError("text was typed before `hello` built the reader edge")
		}
		return adapters
	}
}
