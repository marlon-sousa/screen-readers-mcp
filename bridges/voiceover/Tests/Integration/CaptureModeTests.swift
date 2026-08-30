// HEADLESS INTEGRATION -- THE MARKER FILE, WRITTEN BY THE BRIDGE AND READ BY THE
// CAPTURE VOICE, with both halves real and no VoiceOver anywhere.
//
// WHY THIS TIER EXISTS FOR ONE SMALL FILE. The marker is a wire contract between
// two PROCESSES: the bridge writes it, and a sandboxed speech provider the system
// owns reads it once per utterance. Their unit tests each assert their own side,
// which is exactly the shape of a defect nobody notices -- a renamed field, a
// number written where a boolean is read -- and the failure mode is a screen
// reader that does not go quiet when an agent was promised it would, or worse,
// one that does not come back.
//
// So this suite imports both modules and asserts the round trip, including the
// two properties hard invariant 3 rests on in its macOS form:
//
//   * a marker nobody refreshes EXPIRES, so a dead bridge un-mutes the machine
//     with no code of ours running;
//   * a live session's marker is not silence, because the channel carries the
//     user's own voice in both modes.

import CaptureVoice
import Fakes
import Foundation
import Testing

@testable import VoiceOverBridgeAdapters

@Suite("capture mode, across the two processes")
struct CaptureModeTests {
	/// The bridge's writer and the extension's reader, pointed at one file.
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
		// Rule 0: pass-through re-speaks in the user's own voice, so capture is
		// acoustically invisible. If presence alone meant silence, this session
		// would have muted the machine.
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
		// The whole of hard invariant 3 on macOS. Nothing is released here and
		// nothing is deleted: the file is left exactly as a SIGKILLed bridge would
		// leave it, and the clock moves past the lease.
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
		// REAL TIME, AND A TINY LEASE, deliberately. The expiry test above can move
		// an injected clock because it never rewrites the file; this one is about
		// the mtime a real write leaves behind, and no injected clock reaches
		// that -- so the lease is shortened instead of the clock being stretched.
		// The whole test spends under a second.
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
		// And when the renewals stop, so does the silence.
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
