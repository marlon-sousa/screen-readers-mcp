// Mirrors Sources/VoiceOverBridgeAdapters/VoiceOverAdapterFactory.swift.
//
// THE REFUSAL IS THE TEST. Without it this class would be a leaf -- it makes no
// other decision at this entry -- and with it, it is the one place that says what
// a capture mode means. 13.6 is the entry that removes the refusal, and it should
// have to delete a named test to do it.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("VoiceOverAdapterFactory")
struct VoiceOverAdapterFactoryTests {
	@Test("a live session is built, and the set remembers the mode it was built for")
	func liveIsBuilt() throws {
		let set = try VoiceOverAdapterFactory(capturePath: unusedCapturePath()).build(mode: .live)
		#expect(set.mode == .live)
	}

	@Test("a silent session is REFUSED, because nothing here can keep that promise yet")
	func silentIsRefusedUntilThereIsSilence() {
		// `silent` is a promise about a human's ears: the reader keeps talking, the
		// human hears nothing, the agent reads what was said. Establishing a
		// session that reported `mode: silent` while the machine talked normally
		// and nothing was captured would be the one failure the capability gate
		// exists to prevent -- a session that looks established and means
		// something else.
		#expect(throws: AdapterFactoryError.self) {
			try VoiceOverAdapterFactory(capturePath: unusedCapturePath()).build(mode: .silent)
		}
	}

	@Test("the refusal names the entry that will lift it, and what to do meanwhile")
	func theRefusalIsActionable() {
		do {
			_ = try VoiceOverAdapterFactory(capturePath: unusedCapturePath()).build(mode: .silent)
			Issue.record("expected silent mode to be refused")
		} catch let error as AdapterFactoryError {
			#expect(error.description.contains("13.6"))
			#expect(error.description.contains("live"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}
}
