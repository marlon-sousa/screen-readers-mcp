// Mirrors Sources/VoiceOverBridgeAdapters/VoiceOverPrefsModifierStore.swift.
//
// EVERY TEST HERE IS ABOUT NOT LOSING THE OTHER 119 KEYS. That file holds
// somebody's pitch, rate, volume, voice, Quick Nav and rotor, this repository has
// already destroyed a blind person's speech settings once by rewriting a
// preference the coarse way (spec 0047 finding 17, and the 2026-09-02 field
// report's hand recovery), and the class exists to make the careful way the only
// way. So the assertions are: exactly one key moved, the file went back where it
// came from, in the format it was in, and a write that did not take is a failure
// rather than a silence.

import Foundation
import Fakes
import Testing
import VoiceOverBridgeDomain

@testable import VoiceOverBridgeAdapters

@Suite("VoiceOverPrefsModifierStore")
struct VoiceOverPrefsModifierStoreTests {
	private let home = "/Users/someone"
	private var current: String { VoiceOverPreferencesFile.current(home: home) }
	private var legacy: String { VoiceOverPreferencesFile.legacy(home: home) }

	/// A machine with a realistically busy preference file, and a writer wired so
	/// that a write really does change what the reader answers next -- which is
	/// what a real file does, and what makes the read-back check meaningful.
	private func machine(
		at path: String? = nil,
		settings: [String: Any] = ["SCRVoicePitch": 0.4, "SCRVoiceRate": 0.6, "SCRSpeechVolume": 1.0],
		format: PropertyListSerialization.PropertyListFormat = .binary
	) -> (FakePlistReader, FakePlistWriter, VoiceOverPrefsModifierStore) {
		let reader = FakePlistReader()
		let writer = FakePlistWriter()
		reader.plists[path ?? current] = settings
		reader.formats[path ?? current] = format
		writer.onWrite = { plist, at in reader.plists[at] = plist }
		return (reader, writer, VoiceOverPrefsModifierStore(reader: reader, writer: writer, home: home))
	}

	@Test("it writes exactly ONE key and leaves every other setting alone")
	func exactlyOneKeyMoves() throws {
		let (reader, writer, store) = machine()
		try store.store(.controlOption)

		let written = try #require(writer.writes.first?.plist)
		#expect(written["SCRKeysToUseForVOModifier"] as? String == "SCRVOModifierControlOption")
		// The three the person chose, still exactly as they chose them. This is the
		// assertion that would have caught `defaults import`'s whole-domain replace.
		#expect(written["SCRVoicePitch"] as? Double == 0.4)
		#expect(written["SCRVoiceRate"] as? Double == 0.6)
		#expect(written["SCRSpeechVolume"] as? Double == 1.0)
		#expect(reader.plists[current]?.count == 4)
	}

	@Test("it writes back the file it READ, and in the format it was in")
	func itWritesBackWhereItRead() throws {
		// A binary plist silently re-serialized as XML is a change nobody reviews
		// and every instrument in this repo suddenly disagrees with.
		let (_, writer, store) = machine(format: .binary)
		try store.store(.capsLock)
		#expect(writer.writes.first?.path == current)
		#expect(writer.writes.first?.format == .binary)
	}

	@Test("an XML file stays XML")
	func itPreservesXml() throws {
		let (_, writer, store) = machine(format: .xml)
		try store.store(.controlOption)
		#expect(writer.writes.first?.format == .xml)
	}

	@Test("the LEGACY file is written when it is the one that answers")
	func itFallsBackToTheLegacyPath() throws {
		// Same order the read-only setting beside it uses, and it has to be: a
		// machine where the reader reads one file and the writer writes the other is
		// a machine where nothing this bridge does takes effect.
		let (_, writer, store) = machine(at: legacy)
		try store.store(.controlOption)
		#expect(writer.writes.first?.path == legacy)
	}

	@Test("`unknown` is refused BY NAME, because it is not a modifier at all")
	func unknownIsNotAValue() {
		let (_, writer, store) = machine()
		#expect(throws: ReaderModifierStoreError.self) { try store.store(.unknown) }
		// AND NOTHING WAS WRITTEN. `unknown` means "I could not read the file", and
		// writing it would mean inventing a modifier for somebody.
		#expect(writer.writes.isEmpty)
	}

	@Test("a file that cannot be read is a failure, never a fresh file")
	func anUnreadableFileIsNotRewritten() {
		let reader = FakePlistReader()
		let writer = FakePlistWriter()
		let store = VoiceOverPrefsModifierStore(reader: reader, writer: writer, home: home)
		#expect(throws: ReaderModifierStoreError.self) { try store.store(.controlOption) }
		// THE IMPORTANT HALF: it did not write a one-key plist over a file it could
		// not parse, which would replace 120 settings with one.
		#expect(writer.writes.isEmpty)
	}

	@Test("a write that did not TAKE is reported, not assumed")
	func aWriteThatDidNotLandIsAFailure() {
		// Spec 0047 finding 17 stood as a fact for weeks because a preference was
		// re-read from a cache and the evidence of the write was gone before anybody
		// looked. So the class reads the key back, and this is the control for that.
		let reader = FakePlistReader()
		let writer = FakePlistWriter()
		reader.plists[current] = ["SCRVoicePitch": 0.4]
		// No `onWrite`: the write is accepted and the file does not change.
		let store = VoiceOverPrefsModifierStore(reader: reader, writer: writer, home: home)
		#expect(throws: ReaderModifierStoreError.self) { try store.store(.controlOption) }
	}

	@Test("a file that came back SMALLER is a loud failure")
	func aShrunkenFileIsReported() {
		// The check that makes "accounted for exactly" checkable rather than hoped
		// for. Today's live run was 120 keys -> 120; a drop means this class ate
		// somebody's settings, and the message says to restore from a backup rather
		// than to try again.
		let reader = FakePlistReader()
		let writer = FakePlistWriter()
		reader.plists[current] = ["SCRVoicePitch": 0.4, "SCRVoiceRate": 0.6, "SCRSpeechVolume": 1.0]
		writer.onWrite = { _, at in
			reader.plists[at] = ["SCRKeysToUseForVOModifier": "SCRVOModifierControlOption"]
		}
		let store = VoiceOverPrefsModifierStore(reader: reader, writer: writer, home: home)
		do {
			try store.store(.controlOption)
			Issue.record("expected a shrunken file to be refused")
		} catch let failure as ReaderModifierStoreError {
			#expect(failure.description.contains("LOST SETTINGS"))
			#expect(failure.description.contains("3 keys before"))
		} catch {
			Issue.record("expected a ReaderModifierStoreError")
		}
	}

	@Test("a file that GREW is fine -- that is the reader doing its job")
	func agrownFileIsNotAFailure() throws {
		// Asymmetric on purpose: VoiceOver is running while this happens and writes
		// its own keys whenever it likes. Only a shrinking file is evidence of harm.
		let reader = FakePlistReader()
		let writer = FakePlistWriter()
		reader.plists[current] = ["SCRVoicePitch": 0.4]
		writer.onWrite = { plist, at in
			var grown = plist
			grown["SCRSomethingVoiceOverJustWrote"] = 1
			reader.plists[at] = grown
		}
		let store = VoiceOverPrefsModifierStore(reader: reader, writer: writer, home: home)
		try store.store(.controlOption)
	}

	@Test("a writer that refuses is reported as ITSELF")
	func aFailedWriteIsReportedAsItself() {
		let (_, writer, store) = machine()
		writer.failure = PlistWriteFailure("the disk is full")
		do {
			try store.store(.controlOption)
			Issue.record("expected the write to fail")
		} catch let failure as ReaderModifierStoreError {
			#expect(failure.description.contains("the disk is full"))
		} catch {
			Issue.record("expected a ReaderModifierStoreError")
		}
	}

	@Test("the three spellings are the READ side's, not a second copy")
	func theSpellingsAreShared() {
		// Two spellings of one preference is how a reader and a writer come to
		// disagree about somebody's keyboard, so the table is read from the setting
		// rather than duplicated here.
		for (recorded, setting) in VoiceOverPrefsModifierSetting.values {
			#expect(VoiceOverPrefsModifierStore.recordedValue(for: setting) == recorded)
		}
		#expect(VoiceOverPrefsModifierStore.recordedValue(for: .unknown) == nil)
	}
}
