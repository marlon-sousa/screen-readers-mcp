// Headless integration: the marker file written by the bridge and read by the capture voice, both halves real.

import CaptureVoice
import Fakes
import Foundation
import Testing

@testable import VoiceOverBridgeAdapters

@Suite("capture mode, across the two processes")
struct CaptureModeTests {
	private func halves(lease: TimeInterval = 30, now: @escaping () -> Date = Date.init)
		-> (bridge: MarkerFileSilenceControl, extensionSide: MarkerFileCaptureModeSource, path: String)
	{
		let path = unusedMarkerPath()
		return (
			MarkerFileSilenceControl(path: path),
			MarkerFileCaptureModeSource(path: path, lease: lease, now: now),
			path
		)
	}

	@Test("with no session at all, the extension speaks")
	func noSessionSpeaks() {
		let (_, reader, _) = halves()
		#expect(reader.directive == .passThrough)
	}

	@Test("a SILENT session is read as silence, carrying the user's own voice")
	func silenceCrossesTheGap() throws {
		let (bridge, reader, _) = halves()
		defer { bridge.release() }
		try bridge.begin(preferredVoice: "com.apple.eloquence.pt-BR.Reed")
		try bridge.suppress()
		#expect(reader.directive.silent)
		#expect(reader.directive.preferredVoice == "com.apple.eloquence.pt-BR.Reed")
	}

	@Test("a LIVE session is NOT read as silence, and still carries the voice")
	func liveCrossesTheGap() throws {
		let (bridge, reader, _) = halves()
		defer { bridge.release() }
		try bridge.begin(preferredVoice: "com.apple.eloquence.pt-BR.Reed")
		#expect(reader.directive.silent == false)
		#expect(reader.directive.preferredVoice == "com.apple.eloquence.pt-BR.Reed")
	}

	@Test("a lift is read on the very next utterance")
	func aLiftIsImmediate() throws {
		let (bridge, reader, _) = halves()
		defer { bridge.release() }
		try bridge.begin(preferredVoice: nil)
		try bridge.suppress()
		#expect(reader.directive.silent)
		try bridge.passThrough()
		#expect(reader.directive.silent == false)
	}

	@Test("A BRIDGE THAT DIES UN-MUTES THE MACHINE, with no code of ours running")
	func theLeaseExpires() throws {
		var now = Date()
		let (bridge, reader, path) = halves(lease: 30, now: { now })
		defer { try? FileManager.default.removeItem(atPath: path) }
		try bridge.begin(preferredVoice: "com.apple.eloquence.pt-BR.Reed")
		try bridge.suppress()
		#expect(reader.directive.silent)

		now = now.addingTimeInterval(31)
		#expect(reader.directive == .passThrough)
	}

	@Test("a session that keeps renewing keeps its silence")
	func renewalHoldsTheSilence() throws {
		// Real time with a tiny lease: the lease is read from a real write's mtime, which no injected clock reaches.
		let lease: TimeInterval = 0.3
		let (bridge, reader, _) = halves(lease: lease)
		defer { bridge.release() }
		try bridge.begin(preferredVoice: nil)
		try bridge.suppress()
		for _ in 0..<3 {
			Thread.sleep(forTimeInterval: lease * 0.6)
			bridge.renew()
			#expect(reader.directive.silent)
		}
		Thread.sleep(forTimeInterval: lease * 1.5)
		#expect(reader.directive == .passThrough)
	}

	@Test("releasing the marker is read as pass-through immediately, not after a lease")
	func releaseIsImmediate() throws {
		let (bridge, reader, _) = halves()
		try bridge.begin(preferredVoice: nil)
		try bridge.suppress()
		bridge.release()
		#expect(reader.directive == .passThrough)
	}
}
