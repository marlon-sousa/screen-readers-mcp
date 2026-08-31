// ROLE: controller -- what this reader says about holding the stance this session
// declared.
//
// BUILT BY: Registry. Holds nothing: a stateless singleton like every handler but
// `hello`, because the persona it answers for is on the SessionContext.
// READS: GuidanceDocuments, and the context's `persona`. Touches no port, no
// adapter and no reader -- it composes files.
//
// IT TAKES NO PARAMETERS, AND THAT IS A DECISION RATHER THAN AN OVERSIGHT (spec
// 0029, 4.3; protocol.md §5). The persona was fixed at `hello`, so this answers
// for it and for nothing else. A `persona` argument would let an agent fetch the
// validator's instructions from a session standing in as a user -- which quietly
// undoes what declaring a stance is FOR, and raises a question about what happens
// when the two disagree that nobody needs to answer.
//
// IT NEVER REJECTS A PERSONA IT DOES NOT KNOW. protocol.md §4 requires that, and
// the reason is a release argument rather than a courtesy: if an unfamiliar value
// could fail, adding a fourth persona to the server would mean a synchronised
// release across every bridge in the field. So an unknown one gets the common
// section -- the larger half of what it needed -- with `recognised: false` saying
// out loud that the rest is missing. Silence would leave the agent believing it
// had been instructed when it had not.
//
// `mutatesReader` IS FALSE AND SO IS EVERY OTHER FLAG'S EXCEPTION: this reads
// files. It cannot fail because of anything about the machine, only because of
// how this build was assembled -- see GuidanceDocuments, which raises rather than
// returning an empty document.

import ScreenReaderWire

public final class GetGuidanceHandler: CommandHandler {
	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		try GetGuidanceHandler.guidance(for: context.persona)
	}

	/// The result, composed for one persona.
	///
	/// STATIC AND SHARED WITH `hello`, which sends the same document in its own
	/// result so that a session gets it without a second round trip (protocol.md
	/// §3). The contract requires both routes to describe ONE document, so there
	/// is one place that builds it -- two would be a handshake and a command that
	/// agree today.
	static func guidance(for persona: String) throws -> GetGuidanceResult {
		let composed = try GuidanceDocuments.guidance(for: persona)
		return GetGuidanceResult(
			persona: persona,
			recognised: composed.recognised,
			text: composed.text
		)
	}
}
