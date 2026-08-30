// Mirrors Sources/VoiceOverBridgeAdapters/MarkerFileSilenceControl.swift.
//
// IT DRIVES A REAL FILE IN A TEMPORARY DIRECTORY, for the reason FileLineTailer's
// test does: every decision this class makes is about what a real filesystem
// does -- that a rewrite MOVES THE MODIFICATION TIME, that a replace is whole
// rather than partial, that a delete is a delete -- and a fake seam would only
// prove they behave as the fake was written to. The lease is a contract between
// two processes about an mtime, so an mtime is what this asserts.
//
// AND IT READS BACK THROUGH THE EXTENSION'S OWN PARSER where it can, because the
// file is a wire contract in miniature and two halves that each pass their own
// tests can still disagree about the bytes.

import Foundation
import Fakes
import Testing

@testable import VoiceOverBridgeAdapters

@Suite("MarkerFileSilenceControl")
struct MarkerFileSilenceControlTests {
	private func marker() -> (control: MarkerFileSilenceControl, path: String) {
		let path = unusedMarkerPath()
		return (MarkerFileSilenceControl(path: path), path)
	}

	private func contents(_ path: String) throws -> [String: Any] {
		let data = try Data(contentsOf: URL(fileURLWithPath: path))
		return try #require(
			try JSONSerialization.jsonObject(with: data) as? [String: Any])
	}

	private func modified(_ path: String) throws -> Date {
		try #require(
			try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)
	}

	@Test("nothing is written until a session begins: an idle bridge mutes nothing")
	func nothingUntilBegun() {
		let (control, path) = marker()
		control.renew()
		#expect(FileManager.default.fileExists(atPath: path) == false)
		#expect(control.isSuppressing == false)
	}

	@Test("a LIVE session writes a marker too, saying it is not silent")
	func liveWritesANotSilentMarker() throws {
		// The channel carries the user's own voice in both modes, so presence
		// cannot mean silence -- if it did, every live session would mute the
		// machine.
		let (control, path) = marker()
		defer { control.release() }
		try control.begin(preferredVoice: "com.apple.eloquence.pt-BR.Reed")
		#expect(try contents(path)["silent"] as? Bool == false)
		#expect(try contents(path)["voice"] as? String == "com.apple.eloquence.pt-BR.Reed")
		#expect(control.isSuppressing == false)
	}

	@Test("suppressing says so, and keeps carrying the voice")
	func suppressWrites() throws {
		let (control, path) = marker()
		defer { control.release() }
		try control.begin(preferredVoice: "com.apple.eloquence.pt-BR.Reed")
		try control.suppress()
		#expect(try contents(path)["silent"] as? Bool == true)
		#expect(try contents(path)["voice"] as? String == "com.apple.eloquence.pt-BR.Reed")
		#expect(control.isSuppressing)
	}

	@Test("no preferred voice is written as an empty field, which the other half reads as none")
	func noVoiceIsEmpty() throws {
		let (control, path) = marker()
		defer { control.release() }
		try control.begin(preferredVoice: nil)
		#expect(try contents(path)["voice"] as? String == "")
	}

	@Test("RENEWING MOVES THE MODIFICATION TIME: that is the whole lease mechanism")
	func renewingMovesTheMtime() throws {
		let (control, path) = marker()
		defer { control.release() }
		try control.begin(preferredVoice: nil)
		let first = try modified(path)
		// A filesystem's mtime resolution is coarse enough that two writes in the
		// same instant can share one, so this waits past it rather than asserting
		// something the filesystem never promised.
		Thread.sleep(forTimeInterval: 0.02)
		control.renew()
		#expect(try modified(path) > first)
	}

	@Test("renewing does not change what the marker says")
	func renewingPreservesTheDirective() throws {
		let (control, path) = marker()
		defer { control.release() }
		try control.begin(preferredVoice: "com.apple.voice")
		try control.suppress()
		control.renew()
		#expect(try contents(path)["silent"] as? Bool == true)
		#expect(try contents(path)["voice"] as? String == "com.apple.voice")
	}

	@Test("passing through flips the marker in place, so the next utterance is heard")
	func passThroughFlips() throws {
		let (control, path) = marker()
		defer { control.release() }
		try control.begin(preferredVoice: nil)
		try control.suppress()
		try control.passThrough()
		#expect(try contents(path)["silent"] as? Bool == false)
		#expect(control.isSuppressing == false)
	}

	@Test("releasing DELETES the marker, and renewing afterwards does not resurrect it")
	func releaseDeletes() throws {
		let (control, path) = marker()
		try control.begin(preferredVoice: nil)
		try control.suppress()
		control.release()
		#expect(FileManager.default.fileExists(atPath: path) == false)
		#expect(control.isSuppressing == false)
		// A released session is over. A renewal from a stale caller must not put
		// the machine back into silence behind everyone's back.
		control.renew()
		#expect(FileManager.default.fileExists(atPath: path) == false)
	}

	@Test("releasing twice, or releasing what was never begun, is not an error")
	func releaseIsIdempotent() {
		let (control, _) = marker()
		control.release()
		control.release()
	}

	@Test("the marker path is derived the way the EXTENSION derives it")
	func theDerivationMatches() {
		// Two processes must compute one path from one rule or they never meet.
		// Inside the sandbox the extension's own home IS its container, so it
		// writes <home>/voiceover-capture-silent and the system puts that here.
		#expect(
			MarkerFileSilenceControl.containerMarkerPath(home: "/Users/somebody")
				== "/Users/somebody/Library/Containers/\(captureExtensionBundleID)/Data/voiceover-capture-silent"
		)
	}

	@Test("what this side writes is what the OTHER side reads: silent, with the voice")
	func theTwoHalvesAgree() throws {
		// The bytes are the contract. This asserts them through the shape the
		// extension's own parser expects -- keys, types and all -- because two
		// halves that each pass their own tests can still disagree about a field
		// name, and the failure would be a machine that does not go quiet.
		let (control, path) = marker()
		defer { control.release() }
		try control.begin(preferredVoice: "com.apple.eloquence.pt-BR.Reed")
		try control.suppress()
		let written = try contents(path)
		#expect(written.keys.sorted() == ["silent", "voice"])
		#expect(written["silent"] is Bool)
		#expect(written["voice"] is String)
	}
}
