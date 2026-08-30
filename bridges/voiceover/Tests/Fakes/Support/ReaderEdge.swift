// SCAFFOLDING, not a port double -- Support/, for the same reason CapturePath is.
//
// IT EXISTS TO MAKE ONE MISTAKE UNAVAILABLE. `VoiceOverAdapterFactory` takes a
// ProviderLifecycle, and the REAL one writes the preference that decides which
// voice VoiceOver speaks with. A test that built the real lifecycle would, on
// the developer's own machine, change the voice their screen reader is using --
// and if it failed half-way, leave it changed. That is not a flaky test, it is a
// person unable to hear their computer properly until they notice.
//
// So every test that needs a factory gets one from here, with a fake lifecycle,
// a capture path nothing writes and a marker path nothing reads. The ONLY place
// the real lifecycle is built is Wiring, and the only thing that runs Wiring's
// version is a bridge somebody started deliberately.

import Foundation
import ScreenReaderWire
import VoiceOverBridgeAdapters
import VoiceOverBridgeDomain

/// A factory that touches nothing outside this test's own temporary files.
public func testAdapterFactory(
	capturePath: String = unusedCapturePath(),
	markerPath: String = unusedMarkerPath(),
	lifecycle: any ProviderLifecycle = FakeProviderLifecycle()
) -> VoiceOverAdapterFactory {
	VoiceOverAdapterFactory(capturePath: capturePath, markerPath: markerPath, lifecycle: lifecycle)
}

/// An AdapterSet of doubles, for tests that install a reader edge by hand.
///
/// The three fields arrived one entry at a time and will keep doing so, so a
/// test that spells the initializer out is a test that has to be edited by every
/// future entry for reasons that have nothing to do with what it asserts.
public func fakeAdapterSet(
	mode: CaptureMode = .live,
	speechSource: FakeSpeechSource = FakeSpeechSource(),
	silenceControl: FakeSilenceControl = FakeSilenceControl(),
	providerLifecycle: FakeProviderLifecycle = FakeProviderLifecycle()
) -> AdapterSet {
	AdapterSet(
		mode: mode,
		speechSource: speechSource,
		silenceControl: silenceControl,
		providerLifecycle: providerLifecycle
	)
}
