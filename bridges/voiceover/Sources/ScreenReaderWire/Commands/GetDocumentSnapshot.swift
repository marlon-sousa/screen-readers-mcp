// ROLE: entity -- `getDocumentSnapshot`'s params and result, and the line shape
// and truncation vocabulary the result carries.
//
// Pure. Not implemented by this bridge: `document` is not in its capability set.
//
// `hasDocument == false` IS THE COMMON ANSWER AND NOT A FAILURE -- focus is
// frequently not in a document at all. `truncatedBy` names WHICH bound stopped
// the snapshot, so a caller can raise that one rather than guessing between two.

public struct DocumentSnapshotParams: Codable, Equatable, Sendable {
	public var fromLine: Int = 0
	/// 0 means "the reader's own bound", not "no bound": an unbounded snapshot
	/// of a long document is how a caller reads a truncated answer believing it
	/// is whole.
	public var maxLines: Int = 0
	public var maxChars: Int = 0

	public init(fromLine: Int = 0, maxLines: Int = 0, maxChars: Int = 0) {
		self.fromLine = fromLine
		self.maxLines = maxLines
		self.maxChars = maxChars
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		fromLine = try box.decode(Int.self, forKey: .fromLine, orDefault: fromLine)
		maxLines = try box.decode(Int.self, forKey: .maxLines, orDefault: maxLines)
		maxChars = try box.decode(Int.self, forKey: .maxChars, orDefault: maxChars)
	}
}

public struct DocumentSnapshotResult: Codable, Equatable, Sendable {
	public var hasDocument: Bool
	public var capturedAt: String
	public var title: String = ""
	public var lines: [SnapshotLine] = []
	public var fromLine: Int = 0
	public var toLine: Int = 0
	public var truncatedBy: TruncatedBy = TruncatedBy.none

	public init(
		hasDocument: Bool,
		capturedAt: String,
		title: String = "",
		lines: [SnapshotLine] = [],
		fromLine: Int = 0,
		toLine: Int = 0,
		truncatedBy: TruncatedBy = TruncatedBy.none
	) {
		self.hasDocument = hasDocument
		self.capturedAt = capturedAt
		self.title = title
		self.lines = lines
		self.fromLine = fromLine
		self.toLine = toLine
		self.truncatedBy = truncatedBy
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		hasDocument = try box.decode(Bool.self, forKey: .hasDocument)
		capturedAt = try box.decode(String.self, forKey: .capturedAt)
		title = try box.decode(String.self, forKey: .title, orDefault: title)
		lines = try box.decode([SnapshotLine].self, forKey: .lines, orDefault: lines)
		fromLine = try box.decode(Int.self, forKey: .fromLine, orDefault: fromLine)
		toLine = try box.decode(Int.self, forKey: .toLine, orDefault: toLine)
		truncatedBy = try box.decode(TruncatedBy.self, forKey: .truncatedBy, orDefault: truncatedBy)
	}
}

/// One line of the document, carrying its own number so a caller can ask for
/// more from where it stopped.
public struct SnapshotLine: Codable, Equatable, Sendable {
	public var line: Int
	public var text: String

	public init(line: Int, text: String) {
		self.line = line
		self.text = text
	}
}

/// Which bound stopped the snapshot. `none` means nothing did -- the snapshot is
/// the whole document.
public enum TruncatedBy: String, Codable, CaseIterable, Sendable {
	case none
	case maxLines
	case maxChars
}
