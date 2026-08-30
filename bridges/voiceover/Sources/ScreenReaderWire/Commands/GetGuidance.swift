// ROLE: entity -- `getGuidance`'s result. The command has no params.
//
// Pure. Carried by HelloResult too, so a session gets the reader's own guidance
// without a second round trip; the type lives here, with the command named after
// it.
//
// `recognised` SAYS WHETHER THE PERSONA WAS KNOWN, and it is not decoration: an
// unrecognised persona still gets guidance -- the general text -- and a caller
// that could not tell the difference would believe it had persona-specific
// advice when it had not.
//
// The text itself is a DOCUMENT, which by the repo's rule is a .md file beside
// the package that serves it and never a string literal in code.

public struct GetGuidanceResult: Codable, Equatable, Sendable {
	public var persona: String
	public var recognised: Bool
	public var text: String

	public init(persona: String, recognised: Bool, text: String) {
		self.persona = persona
		self.recognised = recognised
		self.text = text
	}
}
