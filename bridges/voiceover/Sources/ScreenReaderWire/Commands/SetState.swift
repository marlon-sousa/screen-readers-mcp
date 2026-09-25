// ROLE: entity, `setState`'s params and result.

public struct SetStateParams: Codable, Equatable, Sendable {
	/// nil means leave it alone, which differs from `.none`.
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
