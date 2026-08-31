// SCAFFOLDING, not a port double -- Support/, for the same reason CapturePath is.
//
// IT EXISTS TO MAKE THREE MISTAKES UNAVAILABLE, and none of them is a flaky
// test -- each one changes the developer's own machine.
//
//  * `VoiceOverAdapterFactory` takes a ProviderLifecycle, and the REAL one writes
//    the preference that decides which voice VoiceOver speaks with. A test that
//    built it would change the voice the developer's screen reader is using and,
//    if it failed half-way, leave it changed: a person unable to hear their
//    computer properly until they notice.
//  * It takes a PermissionBroker, and the real one's `request` raises a system
//    consent dialog and leaves the process on a list that STAYS granted
//    afterwards. There is no undo, and 13.8's whole claim is that this bridge
//    asks for that grant only when a COMMAND is about to post a system event. No
//    test may touch the real grant.
//  * It takes an EventPoster, and the real one types into whatever window the
//    developer has in front of them at that moment -- which since 13.17 includes
//    pressing CHORDS into it. A stray Command-W in a test run closes the window
//    the developer is reading the failure in.
//  * SINCE 13.10 it takes an Announcer and a UserPrompter, and the real ones
//    SPEAK OUT LOUD and OPEN A WINDOW that steals focus -- on a machine that may
//    have a screen reader running, which would then announce a dialog nobody
//    asked for while the developer reads a test failure.
//
// AND SINCE 13.9 IT MAKES A FOURTH MISTAKE UNAVAILABLE, which is a different
// kind: the focus trio (`tree`, `frontmost`, `trust`) changes nothing on the
// machine, but the real ones answer with whatever the developer has in front of
// them RIGHT NOW. A scenario built on those would assert against a desktop
// rather than against this bridge. 13.17's KEYBOARD LAYOUT is the same kind
// again: reading it asks for nothing and changes nothing, and its answer is
// whatever keyboard the developer types on -- Brazilian here, American in CI --
// so a scenario built on the real one would assert against a person's hardware.
//
// So every test that needs a factory gets one from here, with a fake for every
// one of them, a capture path nothing writes and a marker path nothing reads. The ONLY
// place the real ones are built is Wiring, and the only thing that runs Wiring's
// version is a bridge somebody started deliberately.

import Foundation
import ScreenReaderWire
import VoiceOverBridgeAdapters
import VoiceOverBridgeDomain

/// A factory that touches nothing outside this test's own temporary files.
public func testAdapterFactory(
	capturePath: String = unusedCapturePath(),
	markerPath: String = unusedMarkerPath(),
	lifecycle: any ProviderLifecycle = FakeProviderLifecycle(),
	scripts: any AppleScriptRunner = FakeAppleScriptRunner(),
	permissions: any PermissionBroker = FakePermissionBroker(),
	poster: any EventPoster = FakeEventPoster(),
	layout: any KeyboardLayout = FakeKeyboardLayout(),
	tree: any AccessibilityTree = FakeAccessibilityTree(),
	frontmost: any FrontmostApplication = FakeFrontmostApplication(),
	trust: any AccessibilityTrust = FakeAccessibilityTrust(),
	announcer: any Announcer = FakeAnnouncer(),
	prompter: any UserPrompter = FakeUserPrompter()
) -> VoiceOverAdapterFactory {
	VoiceOverAdapterFactory(
		capturePath: capturePath,
		markerPath: markerPath,
		lifecycle: lifecycle,
		scripts: scripts,
		permissions: permissions,
		poster: poster,
		layout: layout,
		tree: tree,
		frontmost: frontmost,
		trust: trust,
		announcer: announcer,
		prompter: prompter
	)
}

/// An AdapterSet of doubles, for tests that install a reader edge by hand.
///
/// The fields arrived one entry at a time and will keep doing so, so a test that
/// spells the initializer out is a test that has to be edited by every future
/// entry for reasons that have nothing to do with what it asserts. Two arrived
/// with 13.7, two more with 13.8, one with 13.9, two with 13.10 and one with
/// 13.17, and this helper is why nothing but the factory noticed any of the five
/// times.
public func fakeAdapterSet(
	mode: CaptureMode = .live,
	speechSource: FakeSpeechSource = FakeSpeechSource(),
	silenceControl: FakeSilenceControl = FakeSilenceControl(),
	providerLifecycle: FakeProviderLifecycle = FakeProviderLifecycle(),
	gestureSender: FakeGestureSender = FakeGestureSender(),
	readerLiveness: FakeReaderLiveness = FakeReaderLiveness(),
	textTyper: FakeTextTyper = FakeTextTyper(),
	keyPresser: FakeKeyPresser = FakeKeyPresser(),
	permissions: FakePermissionBroker = FakePermissionBroker(),
	focusInspector: FakeFocusInspector = FakeFocusInspector(),
	announcer: FakeAnnouncer = FakeAnnouncer(),
	userPrompter: FakeUserPrompter = FakeUserPrompter()
) -> AdapterSet {
	AdapterSet(
		mode: mode,
		speechSource: speechSource,
		silenceControl: silenceControl,
		providerLifecycle: providerLifecycle,
		gestureSender: gestureSender,
		readerLiveness: readerLiveness,
		textTyper: textTyper,
		keyPresser: keyPresser,
		permissions: permissions,
		focusInspector: focusInspector,
		announcer: announcer,
		userPrompter: userPrompter
	)
}
