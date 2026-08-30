// ROLE: entity -- `getState`'s result. The command has no params.
//
// Pure. Carried by SetStateResult, GestureResult and TypeResult as well, which
// is why the type lives with the command that is named after it rather than in
// a file of its own.
//
// THIS BRIDGE DOES NOT ANSWER IT, and that was measured rather than assumed:
// VoiceOver's 45 toggles are richly drivable and almost none is readable -- the
// exceptions live in an undocumented `local.plist` and do not add up to these
// four fields (spec 0046, part 2; board 13.12). So `state` is not in this
// bridge's capability set, and the nested `state` field of a gesture or type
// result stays nil.
//
// `speechMode` IS A RAW STRING while browse mode is an enum, and that is the
// contract's choice: speech modes are a reader's own vocabulary passing through
// as opaque data (spec 0005), and NVDA has changed the set inside a release.

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
