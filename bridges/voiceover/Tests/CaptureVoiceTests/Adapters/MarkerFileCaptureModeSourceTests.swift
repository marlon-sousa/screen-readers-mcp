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
	private func marker(agedBy age: TimeInterval) throws -> (path: String, now: Date) {
		let path = NSTemporaryDirectory() + "lease-\(UUID().uuidString)"
		FileManager.default.createFile(atPath: path, contents: Data())
		let written = Date()
		try FileManager.default.setAttributes([.modificationDate: written], ofItemAtPath: path)
		return (path, written.addingTimeInterval(age))
	}

	@Test("no marker at all means speak, which is the safe answer")
	func absentMeansSpeak() {
		let source = MarkerFileCaptureModeSource(path: NSTemporaryDirectory() + "definitely-absent")
		#expect(source.isSilent == false)
	}

	@Test("a fresh marker means silence")
	func freshMeansSilent() throws {
		let (path, now) = try marker(agedBy: 1)
		defer { try? FileManager.default.removeItem(atPath: path) }
		let source = MarkerFileCaptureModeSource(path: path, lease: 30, now: { now })
		#expect(source.isSilent == true)
	}

	@Test("a marker exactly at the lease is still silence -- the boundary is inclusive")
	func boundaryIsInclusive() throws {
		let (path, now) = try marker(agedBy: 30)
		defer { try? FileManager.default.removeItem(atPath: path) }
		let source = MarkerFileCaptureModeSource(path: path, lease: 30, now: { now })
		#expect(source.isSilent == true)
	}

	@Test("A STALE MARKER MEANS SPEAK: a bridge that died cannot leave the machine mute")
	func staleMeansSpeak() throws {
		let (path, now) = try marker(agedBy: 31)
		defer { try? FileManager.default.removeItem(atPath: path) }
		let source = MarkerFileCaptureModeSource(path: path, lease: 30, now: { now })
		#expect(source.isSilent == false)
	}

	@Test("a marker from far in the past means speak, however long the machine sat there")
	func longDeadBridgeMeansSpeak() throws {
		let (path, now) = try marker(agedBy: 60 * 60 * 24)
		defer { try? FileManager.default.removeItem(atPath: path) }
		let source = MarkerFileCaptureModeSource(path: path, lease: 30, now: { now })
		#expect(source.isSilent == false)
	}

	@Test("refreshing the marker re-arms the lease")
	func refreshRearms() throws {
		let (path, now) = try marker(agedBy: 31)
		defer { try? FileManager.default.removeItem(atPath: path) }
		let source = MarkerFileCaptureModeSource(path: path, lease: 30, now: { now })
		#expect(source.isSilent == false)
		try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: path)
		#expect(source.isSilent == true)
	}
}
