// ROLE: entity, `getGuidance`'s result, also carried by HelloResult; the command has no params.
// `recognised` false means an unknown persona was served the general text.

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
