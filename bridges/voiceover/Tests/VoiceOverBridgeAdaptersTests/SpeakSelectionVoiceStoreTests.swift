// Mirrors Sources/VoiceOverBridgeAdapters/SpeakSelectionVoiceStore.swift.
// The runner is faked: running `defaults` for real would change the voice the developer's screen reader uses.

import Foundation
import Fakes
import Testing

@testable import VoiceOverBridgeAdapters

@Suite("SpeakSelectionVoiceStore")
struct SpeakSelectionVoiceStoreTests {
	private func domain(voice: String = "com.apple.eloquence.pt-BR.Reed") -> Data {
		let record: [String: Any] = [
			"_type": "Speech.VoiceSelection",
			"_version": 0,
			"pitch": 0.4,
			"rate": 0.6,
			"volume": 1.0,
			"voiceId": voice,
		]
		let root: [String: Any] = ["VoiceOverDefaultVoiceSelections": ["pt", record]]
		return try! PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
	}

	private func store(exporting data: Data, exportStatus: Int32 = 0)
		-> (SpeakSelectionVoiceStore, FakeProcessRunner)
	{
		let runner = FakeProcessRunner()
		runner.answers["export"] = ProcessResult(status: exportStatus, standardOutput: data)
		runner.answers["import"] = ProcessResult(status: 0, standardOutput: Data())
		return (SpeakSelectionVoiceStore(runner: runner), runner)
	}

	@Test("the selected voice is read out of the SYSTEM SPEECH domain")
	func readsTheVoice() {
		let (subject, runner) = store(exporting: domain())
		#expect(subject.selectedVoice() == "com.apple.eloquence.pt-BR.Reed")
		#expect(runner.invocations.first?.arguments == ["export", "com.apple.SpeakSelection", "-"])
	}

	@Test("a write PRESERVES THE PLIST TYPES: pitch and rate stay reals, not strings")
	func writePreservesTypes() throws {
		let (subject, runner) = store(exporting: domain())
		try subject.select("org.example.voice")

		let written = try #require(runner.stdin(forVerb: "import"))
		let plist = try PropertyListSerialization.propertyList(from: written, options: [], format: nil)
		let root = try #require(plist as? [String: Any])
		let entries = try #require(root["VoiceOverDefaultVoiceSelections"] as? [Any])
		let record = try #require(entries.compactMap { $0 as? [String: Any] }.first)
		#expect(record["voiceId"] as? String == "org.example.voice")
		#expect(record["pitch"] is NSNumber)
		#expect(record["pitch"] as? String == nil)
		#expect(record["rate"] is NSNumber)
	}

	@Test("everything else in the record is left exactly as it was")
	func writeTouchesOnlyTheVoice() throws {
		let (subject, runner) = store(exporting: domain())
		try subject.select("org.example.voice")
		let written = try #require(runner.stdin(forVerb: "import"))
		let root = try #require(
			try PropertyListSerialization.propertyList(from: written, options: [], format: nil)
				as? [String: Any])
		let entries = try #require(root["VoiceOverDefaultVoiceSelections"] as? [Any])
		let record = try #require(entries.compactMap { $0 as? [String: Any] }.first)
		#expect(record["_type"] as? String == "Speech.VoiceSelection")
		#expect(record["pitch"] as? Double == 0.4)
		#expect(record["rate"] as? Double == 0.6)
		#expect(entries.compactMap { $0 as? String } == ["pt"])
	}

	@Test("the write goes through cfprefsd, on standard input, to the same domain")
	func writesThroughDefaultsImport() throws {
		let (subject, runner) = store(exporting: domain())
		try subject.select("org.example.voice")
		#expect(runner.invocations.last?.arguments == ["import", "com.apple.SpeakSelection", "-"])
	}

	@Test("a domain that cannot be exported is a failure, not a silent nil write")
	func exportFailureThrows() {
		let (subject, _) = store(exporting: Data(), exportStatus: 1)
		#expect(throws: VoiceStoreError.self) { try subject.select("org.example.voice") }
		#expect(subject.selectedVoice() == nil)
	}

	@Test("a domain with no selection record REFUSES rather than inventing one")
	func noRecordRefuses() {
		let empty = try! PropertyListSerialization.data(
			fromPropertyList: ["VoiceOverDefaultVoiceSelections": ["pt"]], format: .xml, options: 0)
		let (subject, _) = store(exporting: empty)
		#expect(throws: VoiceStoreError.self) { try subject.select("org.example.voice") }
	}

	@Test("output that is not a plist at all is a failure with a readable reason")
	func garbageThrows() {
		let (subject, _) = store(exporting: Data("not a plist".utf8))
		#expect(subject.selectedVoice() == nil)
		#expect(throws: VoiceStoreError.self) { try subject.select("org.example.voice") }
	}

	@Test("a failed import is reported, so a write that did not happen is never reported as one")
	func importFailureThrows() {
		let runner = FakeProcessRunner()
		runner.answers["export"] = ProcessResult(status: 0, standardOutput: domain())
		runner.answers["import"] = ProcessResult(status: 1, standardOutput: Data(), standardError: "denied")
		let subject = SpeakSelectionVoiceStore(runner: runner)
		#expect(throws: VoiceStoreError.self) { try subject.select("org.example.voice") }
	}
}
