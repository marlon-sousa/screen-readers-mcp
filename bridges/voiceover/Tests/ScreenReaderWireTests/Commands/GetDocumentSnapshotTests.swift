// Mirrors Sources/ScreenReaderWire/Commands/GetDocumentSnapshot.swift.

import Testing

@testable import ScreenReaderWire

@Suite("getDocumentSnapshot")
struct GetDocumentSnapshotTests {
	@Test("an empty request means the reader's own bounds, spelled as zeroes")
	func defaults() throws {
		let params = try WireJSON.decode(DocumentSnapshotParams.self, "{}")
		#expect(params.fromLine == 0)
		#expect(params.maxLines == 0)
		#expect(params.maxChars == 0)
	}

	@Test("no document is the common answer and not a failure")
	func noDocument() throws {
		let result = try WireJSON.decode(
			DocumentSnapshotResult.self,
			#"{"hasDocument":false,"capturedAt":"2026-08-30T09:00:00Z"}"#
		)
		#expect(!result.hasDocument)
		#expect(result.lines.isEmpty)
		#expect(result.title.isEmpty)
		#expect(result.truncatedBy == TruncatedBy.none)
	}

	@Test("truncation names which bound stopped it, so a caller raises that one")
	func truncationIsNamed() throws {
		let json = """
		{"hasDocument":true,"capturedAt":"2026-08-30T09:00:00Z","title":"README",\
		"lines":[{"line":1,"text":"first"}],"fromLine":1,"toLine":2,"truncatedBy":"maxChars"}
		"""
		let result = try WireJSON.decode(DocumentSnapshotResult.self, json)
		#expect(result.truncatedBy == .maxChars)
		#expect(result.lines == [SnapshotLine(line: 1, text: "first")])
	}

	@Test("an unknown truncation reason is refused, because the set is closed")
	func unknownTruncationRefused() {
		let json = #"{"hasDocument":true,"capturedAt":"t","truncatedBy":"boredom"}"#
		#expect(throws: (any Error).self) {
			try WireJSON.decode(DocumentSnapshotResult.self, json)
		}
	}
}
