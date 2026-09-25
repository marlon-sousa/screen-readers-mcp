// ROLE: entity, the reader's browse or focus mode; `none` means the concept does not apply to what is focused.

public enum BrowseMode: String, Codable, CaseIterable, Sendable {
	case browse
	case focus
	case none
}
