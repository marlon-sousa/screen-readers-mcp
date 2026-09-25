// Test scaffolding: adapter factories and sets whose every side-effecting collaborator is a fake.
// The real lifecycle, permission broker, event poster, announcer and prompter change the developer's machine, so only Wiring may build them.

import Foundation
import ScreenReaderWire
import VoiceOverBridgeAdapters
import VoiceOverBridgeDomain

/// A factory that touches nothing outside this test's own temporary files; `captureProbeSpeaks: false` gives a reader that never answers the capture probe.
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

/// Makes a fake event poster behave like a healthy reader, appending one `synthesize` line to the feed on every key press, not only the probe's.
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

/// Makes a pair of port doubles behave like a reader that speaks on every key press, chaining any existing `onPress`.
public func answerTheCaptureProbe(
	pressing presser: FakeKeyPresser, speaking source: FakeSpeechSource
) {
	let previous = presser.onPress
	presser.onPress = { keystroke in
		previous?(keystroke)
		source.emit(captureProbeUtterance)
	}
}

/// What a fake reader says for the capture probe; it lands at index 1 of every session's buffer.
public let captureProbeUtterance = "capture probe, fake reader"
