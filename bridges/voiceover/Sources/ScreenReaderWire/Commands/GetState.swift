// ROLE: entity, `getState`'s result, also carried by SetStateResult, GestureResult and TypeResult.
// VoiceOver on macOS 15 lets almost none of its toggles be read, so this bridge does not advertise `state`
// and a nested `state` stays nil.

public struct StateResult: Codable, Equatable, Sendable {
	public var browseMode: BrowseMode
	public var speechMode: String
	public var sleepMode: Bool
	public var inputHelp: Bool

	public init(browseMode: BrowseMode, speechMode: String, sleepMode: Bool, inputHelp: Bool) {
		self.browseMode = browseMode
		self.speechMode = speechMode
		self.sleepMode = sleepMode
		self.inputHelp = inputHelp
	}
}
