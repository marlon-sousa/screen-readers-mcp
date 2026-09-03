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
///
/// IT HANDS BACK A HEALTHY MACHINE BY DEFAULT, WHICH SINCE 13.20 INCLUDES A
/// READER THAT SPEAKS. The handshake now climbs the ProviderState ladder and its
/// last rung presses `describe item in voiceover cursor` and requires the
/// utterance to ARRIVE -- so a factory whose fake reader said nothing would be a
/// machine no test could connect to, and every scenario in this suite would fail
/// for a reason none of them is about. `captureProbeSpeaks: false` is how a test
/// asks for the machine where nothing comes back.
///
/// THE WRITE GOES THROUGH THE REAL FEED, on purpose. `capturePath` is this test's
/// own temporary file and the factory builds the REAL `ContainerFileSpeechSource`
/// over the REAL `FileLineTailer`, so an integration handshake proves the whole
/// capture path -- a line appended by another writer, tailed, parsed and
/// buffered -- with no extension and no reader on the machine. The IO lives here,
/// in scaffolding, and never inside a port double.
public func testAdapterFactory(
	capturePath: String = unusedCapturePath(),
	markerPath: String = unusedMarkerPath(),
	lifecycle: any ProviderLifecycle = FakeProviderLifecycle(),
	tools: any ProcessRunner = FakeProcessRunner(),
	permissions: any PermissionBroker = FakePermissionBroker(),
	poster: any EventPoster = FakeEventPoster(),
	applications: any RunningApplications = FakeRunningApplications(),
	layout: any KeyboardLayout = FakeKeyboardLayout(),
	readerModifier: any ReaderModifierSetting = FakeReaderModifierSetting(),
	readerRestart: any ReaderRestart = FakeReaderRestart(),
	changeJournal: any ChangeJournal = FakeChangeJournal(),
	tree: any AccessibilityTree = FakeAccessibilityTree(),
	frontmost: any FrontmostApplication = FakeFrontmostApplication(),
	trust: any AccessibilityTrust = FakeAccessibilityTrust(),
	announcer: any Announcer = FakeAnnouncer(),
	prompter: any UserPrompter = FakeUserPrompter(),
	captureProbeSpeaks: Bool = true
) -> VoiceOverAdapterFactory {
	if captureProbeSpeaks {
		answerTheCaptureProbe(pressing: poster, writingTo: capturePath)
	}
	return VoiceOverAdapterFactory(
		capturePath: capturePath,
		markerPath: markerPath,
		lifecycle: lifecycle,
		tools: tools,
		permissions: permissions,
		poster: poster,
		applications: applications,
		layout: layout,
		readerModifier: readerModifier,
		readerRestart: readerRestart,
		changeJournal: changeJournal,
		tree: tree,
		frontmost: frontmost,
		trust: trust,
		announcer: announcer,
		prompter: prompter
	)
}

/// Make a fake EVENT POSTER behave like a HEALTHY reader: one that speaks when
/// the capture probe is pressed.
///
/// ONE PROBE, BECAUSE THE HANDSHAKE SENDS ONE. It sent two until 13.31 -- an
/// AppleEvent asking the reader its own name at rung 2, and the probe itself at
/// rung 5, both over a script runner this rig had to answer for. Rung 2 reads the
/// running-application list now (13.26) and rung 5 presses a key (13.31), so what
/// is left is a poster that produces speech.
///
/// IT ANSWERS ANY PRESS RATHER THAN MATCHING THE PROBE'S KEYS, and that is the one
/// thing to know before reusing it. The probe reaches this seam as a keycode and a
/// set of flags -- there is no `vo+f7` left in it to match on, and reconstructing
/// one here would be this rig deciding what the layout means. A test that needs to
/// know WHICH keys were pressed asserts on the poster's own record; this only
/// makes the machine one a session can be established on.
///
/// The speech is one `synthesize` line in the capture voice's own feed format,
/// appended when a key goes out. The format is the extension's, not ours to
/// invent: `ContainerFileSpeechSource` reads `event`, `text` and `at`, and a line
/// with no `ssml` is the documented fallback path.
public func answerTheCaptureProbe(pressing poster: any EventPoster, writingTo path: String) {
	guard let fake = poster as? FakeEventPoster else { return }
	let previous = fake.onKeyDown
	fake.onKeyDown = { event in
		previous?(event)
		let line = Data(
			"{\"event\":\"synthesize\",\"text\":\"\(captureProbeUtterance)\",\"at\":0}\n".utf8)
		if let handle = FileHandle(forWritingAtPath: path) {
			handle.seekToEndOfFile()
			handle.write(line)
			try? handle.close()
		} else {
			try? line.write(to: URL(fileURLWithPath: path))
		}
	}
}

/// An AdapterSet of doubles, for tests that install a reader edge by hand.
///
/// The fields arrived one entry at a time and will keep doing so, so a test that
/// spells the initializer out is a test that has to be edited by every future
/// entry for reasons that have nothing to do with what it asserts. Two arrived
/// with 13.7, two more with 13.8, one with 13.9, two with 13.10 and one with
/// 13.17, and this helper is why nothing but the factory noticed any of the five
/// times.
///
/// SINCE 13.20 THE GESTURE SENDER ANSWERS THE CAPTURE PROBE, for the reason the
/// factory above does: the handshake requires an utterance to come back, and a
/// set whose reader is mute is a machine no session can be established on. Here
/// it is a direct `emit` on the fake source rather than a file, because these are
/// port doubles all the way down and there is no feed to tail.
public func fakeAdapterSet(
	mode: CaptureMode = .live,
	speechSource: FakeSpeechSource = FakeSpeechSource(),
	silenceControl: FakeSilenceControl = FakeSilenceControl(),
	providerLifecycle: FakeProviderLifecycle = FakeProviderLifecycle(),
	readerLiveness: FakeReaderLiveness = FakeReaderLiveness(),
	textTyper: FakeTextTyper = FakeTextTyper(),
	keyPresser: FakeKeyPresser = FakeKeyPresser(),
	readerModifier: FakeReaderModifierSetting = FakeReaderModifierSetting(),
	readerRestart: FakeReaderRestart = FakeReaderRestart(),
	changeJournal: FakeChangeJournal = FakeChangeJournal(),
	permissions: FakePermissionBroker = FakePermissionBroker(),
	focusInspector: FakeFocusInspector = FakeFocusInspector(),
	announcer: FakeAnnouncer = FakeAnnouncer(),
	userPrompter: FakeUserPrompter = FakeUserPrompter(),
	captureProbeSpeaks: Bool = true
) -> AdapterSet {
	if captureProbeSpeaks {
		answerTheCaptureProbe(pressing: keyPresser, speaking: speechSource)
	}
	return AdapterSet(
		mode: mode,
		speechSource: speechSource,
		silenceControl: silenceControl,
		providerLifecycle: providerLifecycle,
		readerLiveness: readerLiveness,
		textTyper: textTyper,
		keyPresser: keyPresser,
		readerModifier: readerModifier,
		readerRestart: readerRestart,
		changeJournal: changeJournal,
		permissions: permissions,
		focusInspector: focusInspector,
		announcer: announcer,
		userPrompter: userPrompter
	)
}

/// Make a pair of port doubles behave like a reader that speaks when the capture
/// probe is pressed.
///
/// THE ONE DEFINITION OF A HEALTHY FAKE READER AT THE PORT LEVEL, called by
/// `fakeAdapterSet` here and by `FakeAdapterFactory` beside it. Two copies of it
/// would be two ideas of what a working machine does, and they would differ the
/// first time somebody changed the probe.
///
/// IT WAS A PAIR OF FUNCTIONS UNTIL 13.31 -- one for the probe dispatched as a
/// command name and one for the probe pressed as a key -- because the two routes
/// were the thing under test and a fake that answered whichever it happened to
/// receive could not tell them apart. There is one route now.
///
/// It CHAINS rather than replacing: a test that installed its own `onPress` to
/// make speech arrive as a consequence of ITS keystroke keeps working.
public func answerTheCaptureProbe(
	pressing presser: FakeKeyPresser, speaking source: FakeSpeechSource
) {
	let previous = presser.onPress
	presser.onPress = { keystroke in
		previous?(keystroke)
		source.emit(captureProbeUtterance)
	}
}

/// What a fake reader "says" when the capture proof presses its probe.
///
/// Recognisable on sight, so an assertion that trips over it in a buffer says
/// what put it there. It is REAL SPEECH as far as the session is concerned --
/// the reader was asked to describe its cursor and it did -- so it lands at
/// index 1 of every session's buffer, which is a consequence tests have to
/// account for rather than one the bridge hides.
///
/// The probe is `vo+f7` since 13.31, which is what a person presses to hear the
/// time and date. It was `describe item in voiceover cursor` when this comment was
/// written, and what it asks for is unchanged: something that always speaks and
/// moves nothing.
public let captureProbeUtterance = "capture probe, fake reader"
