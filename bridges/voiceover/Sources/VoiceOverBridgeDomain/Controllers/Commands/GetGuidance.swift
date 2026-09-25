// ROLE: controller for `getGuidance`: this reader's guidance for the persona the session declared.
// BUILT BY: Registry.
// READS: GuidanceDocuments and the context's `persona`; it touches no port.
// An unknown persona is never rejected: it gets the common section with `recognised: false`.

import ScreenReaderWire

public final class GetGuidanceHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		try GetGuidanceHandler.guidance(for: context.persona)
	}

	/// The result for one persona; `hello` sends the same document, so both routes build it here.
	static func guidance(for persona: String) throws -> GetGuidanceResult {
		let composed = try GuidanceDocuments.guidance(for: persona)
		return GetGuidanceResult(
			persona: persona,
			recognised: composed.recognised,
			text: composed.text
		)
	}
}
