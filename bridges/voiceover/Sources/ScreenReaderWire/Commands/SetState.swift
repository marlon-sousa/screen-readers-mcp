// ROLE: entity -- `setState`'s params and result.
//
// Pure. The result carries the WHOLE state after the change plus the list of
// fields that actually moved, so a caller never has to ask again to find out
// what happened -- and an empty `changed` is the honest answer for a request
// that asked for what was already true.

public struct SetStateParams: Codable, Equatable, Sendable {
	/// nil means "leave it alone", which is different from `.none`, the browse
	/// mode a reader reports when the concept does not apply.
	public var browseMode: BrowseMode?

	public init(browseMode: BrowseMode? = nil) {
		self.browseMode = browseMode
	}
}

public struct SetStateResult: Codable, Equatable, Sendable {
	public var state: StateResult
	public var changed: [String] = []

	public init(state: StateResult, changed: [String] = []) {
		self.state = state
		self.changed = changed
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		state = try box.decode(StateResult.self, forKey: .state)
		changed = try box.decode([String].self, forKey: .changed, orDefault: changed)
	}
}
