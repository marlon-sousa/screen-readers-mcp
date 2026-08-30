// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/Observation.swift.
//
// It has a test file because it has BEHAVIOUR -- two conventions that three
// commands now depend on agreeing about, which is the whole reason it stopped
// being written out per handler at 13.7.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("Observation")
struct ObservationTests {
	@Test("each entry keeps the index it occupies, not its position in the list")
	func entriesKeepTheirOwnIndex() {
		// The convention that makes a range resumable: entries with no words are
		// skipped, so position in this array and index in the ring are different
		// numbers -- and only one of them is a coordinate the agent can come back
		// with.
		let entries = Observation.speechEntries([
			(CapturedUtterance(text: "Documents"), 3),
			(CapturedUtterance(text: "folder"), 7),
		])
		#expect(entries.map(\.text) == ["Documents", "folder"])
		#expect(entries.map(\.index) == [3, 7])
	}

	@Test("the emission stamp is FORMATTED here, which is why the entity stores a number")
	func theStampIsFormattedOnce() {
		let entries = Observation.speechEntries([
			(CapturedUtterance(text: "said", emittedAt: 1_700_000_000), 1)
		])
		#expect(entries.first?.emittedAt == Wallclock.format(1_700_000_000))
		#expect(entries.first?.emittedAt.isEmpty == false)
	}

	@Test("`logPosition` is 0 for every entry, stated in ONE place")
	func logPositionIsAlwaysZero() {
		// The honest answer rather than a stub: it is a coordinate into NVDA's log
		// journal, and this reader emits no diagnostic log to position into. Said
		// once, so the day that changes it cannot be half-corrected.
		let entries = Observation.speechEntries([
			(CapturedUtterance(text: "a"), 1), (CapturedUtterance(text: "b"), 2),
		])
		#expect(entries.allSatisfy { $0.logPosition == 0 })
	}

	@Test("nothing in, nothing out")
	func emptyIsEmpty() {
		#expect(Observation.speechEntries([]).isEmpty)
	}
}
