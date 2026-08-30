// Mirrors Sources/VoiceOverBridgeAdapters/SpeakSelectionVoiceStore.swift.
//
// THE TYPE TRAP IS THE TEST, and it is the reason this class is not three lines
// of `defaults write`. A record whose reals arrive as strings is SILENTLY
// REJECTED by VoiceOver, which then rewrites the key with its own choice -- so
// the evidence of the write is gone before anyone looks, and it presents as
// "writing the preference does nothing". That wrong conclusion is spec 0047's
// finding 2, and it stood for an evening.
//
// The runner is faked, so none of this touches the machine's own preferences.
// A test here that ran `defaults` for real would change the voice the developer's
// screen reader speaks with.

import Foundation
import Fakes
import Testing

@testable import VoiceOverBridgeAdapters

@Suite("SpeakSelectionVoiceStore")
struct SpeakSelectionVoiceStoreTests {
	/// The domain as it actually looks on a machine with one language configured:
	/// a flat array alternating a language tag with a record.
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
		// The domain matters as much as the value: reading VoiceOver's own would
		// answer nil forever, which is where an evening went.
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
		// The assertion the whole class exists for.
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
		// The language tag beside the record is still there: the array is not a
		// list of records, and rebuilding it would drop the half we do not own.
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
		// The record's shape is user data -- a language, a pitch, a rate, a volume
		// -- and inventing one would be guessing at values a person chose. A
		// machine that has never had a voice chosen says so.
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
