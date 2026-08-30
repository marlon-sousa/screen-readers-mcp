// Mirrors Sources/CaptureVoice/Adapters/MarkerFileCaptureModeSource.swift.
//
// This adapter used to be a leaf -- one `fileExists`, no decision, no test. It
// makes a decision now (is the lease still good?), and the decision is the one
// that keeps a blind user from being left mute by a crashed bridge, so it is the
// last file in this package that should go untested.

import Foundation
import Testing

@testable import CaptureVoice

@Suite("MarkerFileCaptureModeSource")
struct MarkerFileCaptureModeSourceTests {
	private func marker(agedBy age: TimeInterval, saying contents: String = "{\"silent\":true}")
		throws -> (path: String, now: Date)
	{
		let path = NSTemporaryDirectory() + "lease-\(UUID().uuidString)"
		FileManager.default.createFile(atPath: path, contents: Data(contents.utf8))
		let written = Date()
		try FileManager.default.setAttributes([.modificationDate: written], ofItemAtPath: path)
		return (path, written.addingTimeInterval(age))
	}

	@Test("no marker at all means speak, which is the safe answer")
	func absentMeansSpeak() {
		let source = MarkerFileCaptureModeSource(path: NSTemporaryDirectory() + "definitely-absent")
		#expect(source.directive.silent == false)
	}

	@Test("a fresh marker means silence")
	func freshMeansSilent() throws {
		let (path, now) = try marker(agedBy: 1)
		defer { try? FileManager.default.removeItem(atPath: path) }
		let source = MarkerFileCaptureModeSource(path: path, lease: 30, now: { now })
		#expect(source.directive.silent == true)
	}

	@Test("a marker exactly at the lease is still silence -- the boundary is inclusive")
	func boundaryIsInclusive() throws {
		let (path, now) = try marker(agedBy: 30)
		defer { try? FileManager.default.removeItem(atPath: path) }
		let source = MarkerFileCaptureModeSource(path: path, lease: 30, now: { now })
		#expect(source.directive.silent == true)
	}

	@Test("A STALE MARKER MEANS SPEAK: a bridge that died cannot leave the machine mute")
	func staleMeansSpeak() throws {
		let (path, now) = try marker(agedBy: 31)
		defer { try? FileManager.default.removeItem(atPath: path) }
		let source = MarkerFileCaptureModeSource(path: path, lease: 30, now: { now })
		#expect(source.directive.silent == false)
	}

	@Test("a marker from far in the past means speak, however long the machine sat there")
	func longDeadBridgeMeansSpeak() throws {
		let (path, now) = try marker(agedBy: 60 * 60 * 24)
		defer { try? FileManager.default.removeItem(atPath: path) }
		let source = MarkerFileCaptureModeSource(path: path, lease: 30, now: { now })
		#expect(source.directive.silent == false)
	}

	@Test("refreshing the marker re-arms the lease")
	func refreshRearms() throws {
		let (path, now) = try marker(agedBy: 31)
		defer { try? FileManager.default.removeItem(atPath: path) }
		let source = MarkerFileCaptureModeSource(path: path, lease: 30, now: { now })
		#expect(source.directive.silent == false)
		try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: path)
		#expect(source.directive.silent == true)
	}

	@Test("a fresh marker that says NOT silent is a live session's channel, not silence")
	func freshAndNotSilentSpeaks() throws {
		// A live session keeps a marker too, because the preferred voice has to
		// reach this side in both modes. Presence alone must therefore not mean
		// silence -- if it did, every live session would mute the machine.
		let (path, now) = try marker(agedBy: 1, saying: #"{"silent":false,"voice":"com.apple.Reed"}"#)
		defer { try? FileManager.default.removeItem(atPath: path) }
		let source = MarkerFileCaptureModeSource(path: path, lease: 30, now: { now })
		#expect(source.directive.silent == false)
		#expect(source.directive.preferredVoice == "com.apple.Reed")
	}

	@Test("the preferred voice rides on the marker, and a stale marker carries none")
	func staleCarriesNoVoice() throws {
		let (path, now) = try marker(agedBy: 31, saying: #"{"silent":true,"voice":"com.apple.Reed"}"#)
		defer { try? FileManager.default.removeItem(atPath: path) }
		let source = MarkerFileCaptureModeSource(path: path, lease: 30, now: { now })
		// The lease governs the WHOLE directive: a dead bridge's idea of the
		// user's voice is as expired as its idea of silence.
		#expect(source.directive == .passThrough)
	}

	@Test("contents that do not parse are pass-through, like every other unanswerable question")
	func unparseableMeansSpeak() throws {
		let (path, now) = try marker(agedBy: 1, saying: "not json at all")
		defer { try? FileManager.default.removeItem(atPath: path) }
		let source = MarkerFileCaptureModeSource(path: path, lease: 30, now: { now })
		#expect(source.directive == .passThrough)
	}

	@Test("an empty voice is no voice, not a voice named the empty string")
	func emptyVoiceIsNone() {
		#expect(MarkerFileCaptureModeSource.parse(Data(#"{"silent":true,"voice":""}"#.utf8))
			== CaptureDirective(silent: true, preferredVoice: nil))
	}

	@Test("a marker with no `silent` key is pass-through, because absence is never silence")
	func missingSilentKeyMeansSpeak() {
		#expect(MarkerFileCaptureModeSource.parse(Data(#"{"voice":"com.apple.Reed"}"#.utf8))
			== CaptureDirective(silent: false, preferredVoice: "com.apple.Reed"))
	}
}
