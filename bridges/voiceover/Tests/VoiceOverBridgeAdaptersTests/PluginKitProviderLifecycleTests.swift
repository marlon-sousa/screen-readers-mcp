// Mirrors Sources/VoiceOverBridgeAdapters/PluginKitProviderLifecycle.swift.
//
// EVERY LINE OF PLUGINKIT OUTPUT IN THIS FILE WAS COPIED FROM A REAL RUN on
// macOS 15.0, marker column and tabs included, because the parsing is the kind of
// thing that passes against an invented sample and fails against the machine.
// The important detail is the one that would be guessed wrong: Apple's own speech
// providers carry a BLANK marker, not a `+`, so "registered" cannot mean "starts
// with a plus".
//
// The three seams are faked, so nothing here runs a tool or touches a preference.

import Foundation
import Fakes
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("PluginKitProviderLifecycle")
struct PluginKitProviderLifecycleTests {
	static let bundleID = "org.screen-readers-mcp.spike.capture.voice"
	static let suffix = "org.screen-readers-mcp.spike.capture"
	/// What the system publishes: the extension's bundle id, then ours. It never
	/// equals what the audio unit declared, which is the whole reason for suffixes.
	static let publishedVoice = bundleID + "." + suffix
	static let usersVoice = "com.apple.eloquence.pt-BR.Reed"

	/// A real listing, ours enabled.
	static let listing = """
		     com.apple.texttospeech.SiriAUSP(1.0)\tCE39CFD2-4782-536B-B9D7-C2A3A527CCA7\t2024-09-17 02:00:41 +0000\t/System/Library/PrivateFrameworks/TextToSpeech.framework/PlugIns/SiriAUSP.appex
		+    \(bundleID)(1.0)\tAC706B22-AC35-49A6-A11F-553FCC2FE9D1\t2026-08-29 22:25:07 +0000\t/Users/somebody/CaptureVoice.appex
		     com.apple.ax.MauiTTSSupport.MauiAUSP(1.0)\t58C111DB-4028-5C2E-9F12-540DDD7F01F0\t2024-09-17 02:00:47 +0000\t/System/Library/PrivateFrameworks/TextToSpeechMauiSupport.framework/PlugIns/MauiAUSP.appex
		 (3 plug-ins)
		"""

	private func subject(
		listing text: String = listing,
		listingStatus: Int32 = 0,
		published: [String] = [publishedVoice],
		selected: String? = usersVoice
	) -> (PluginKitProviderLifecycle, FakeVoiceStore, FakeProcessRunner) {
		let runner = FakeProcessRunner()
		runner.answers["-m"] = ProcessResult(status: listingStatus, standardOutput: Data(text.utf8))
		let store = FakeVoiceStore(voice: selected)
		let lifecycle = PluginKitProviderLifecycle(
			runner: runner,
			published: FakePublishedVoices(voices: published),
			store: store,
			extensionBundleID: PluginKitProviderLifecycleTests.bundleID,
			voiceIdentifierSuffix: PluginKitProviderLifecycleTests.suffix
		)
		return (lifecycle, store, runner)
	}

	// -- the state machine ----------------------------------------------------

	@Test("listed, published, not selected: published")
	func published() {
		let (lifecycle, _, _) = subject()
		#expect(lifecycle.state() == .published)
	}

	@Test("listed, published, and ours selected: selected -- never capturing")
	func selected() {
		// `capturing` is evidence, and this class cannot see the feed. Claiming it
		// here would make a dead provider indistinguishable from a working one,
		// which is the exact failure spec 0047's finding 18 warns about.
		let (lifecycle, _, _) = subject(selected: PluginKitProviderLifecycleTests.publishedVoice)
		#expect(lifecycle.state() == .selected)
	}

	@Test("not listed by pluginkit: notRegistered")
	func notListed() {
		let (lifecycle, _, _) = subject(listing: "     com.apple.texttospeech.SiriAUSP(1.0)\tX\tY\tZ")
		#expect(lifecycle.state() == .notRegistered)
	}

	@Test("listed but its voice is not in the machine's list: registered")
	func listedButUnpublished() {
		let (lifecycle, _, _) = subject(published: ["com.apple.voice.compact.pt-BR.Luciana"])
		#expect(lifecycle.state() == .registered)
	}

	@Test("an explicitly DISABLED plug-in is not registered")
	func disabledIsNotRegistered() {
		let disabled = Self.listing.replacingOccurrences(of: "+    \(Self.bundleID)", with: "-    \(Self.bundleID)")
		let (lifecycle, _, _) = subject(listing: disabled)
		#expect(lifecycle.state() == .notRegistered)
	}

	@Test("a BLANK marker still counts as registered, because Apple's own carry one")
	func blankMarkerIsRegistered() {
		let blank = Self.listing.replacingOccurrences(of: "+    \(Self.bundleID)", with: "     \(Self.bundleID)")
		let (lifecycle, _, _) = subject(listing: blank)
		#expect(lifecycle.state() == .published)
	}

	@Test("pluginkit failing to run at all is notRegistered, not a crash")
	func pluginkitFailure() {
		let (lifecycle, _, _) = subject(listing: "", listingStatus: 1)
		#expect(lifecycle.state() == .notRegistered)
	}

	@Test("it asks pluginkit for the SPEECH extension point, verbosely")
	func itAsksTheRightQuestion() {
		let (lifecycle, _, runner) = subject()
		_ = lifecycle.state()
		#expect(
			runner.invocations.first?.arguments == ["-m", "-p", "com.apple.AudioUnit-Speech", "-v"])
	}

	// -- the voice ------------------------------------------------------------

	@Test("the selected voice says whether it is OURS, matched by suffix")
	func selectedVoiceIsClassified() {
		let (theirs, _, _) = subject()
		#expect(theirs.selectedVoice() == SelectedVoice(identifier: Self.usersVoice, isCaptureVoice: false))
		let (ours, _, _) = subject(selected: Self.publishedVoice)
		#expect(ours.selectedVoice()?.isCaptureVoice == true)
	}

	@Test("selecting writes the identifier THE SYSTEM PUBLISHED, not the one we declared")
	func selectsThePublishedIdentifier() throws {
		let (lifecycle, store, _) = subject()
		try lifecycle.selectCaptureVoice()
		#expect(store.writes == [Self.publishedVoice])
		#expect(store.writes.first != Self.suffix)
	}

	@Test("A WRITE THAT DID NOT TAKE IS A FAILURE, and it names the condition nothing else can see")
	func aRejectedWriteIsCaught() {
		// The type trap and the vanished voice both look like this: the write
		// returns cleanly and the value is not what was asked for. Confirming is
		// the only thing that catches either.
		let (lifecycle, store, _) = subject()
		store.rejectsWrites = true
		do {
			try lifecycle.selectCaptureVoice()
			Issue.record("expected the unconfirmed write to be reported")
		} catch let error as ProviderError {
			#expect(error.description.contains(ReaderCondition.captureVoiceNotOfferedByReader.rawValue))
			#expect(error.description.contains("pluginkit -a"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("selecting a voice the machine does not publish reports the state, with its recovery")
	func cannotSelectWhatIsNotPublished() {
		let (lifecycle, store, _) = subject(published: [])
		do {
			try lifecycle.selectCaptureVoice()
			Issue.record("expected a refusal")
		} catch let error as ProviderError {
			#expect(error.description.contains(ReaderCondition.providerNotRunning.rawValue))
			#expect(store.writes.isEmpty)
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("restoring puts the user's own voice back, and confirms that too")
	func restoreConfirms() throws {
		let (lifecycle, store, _) = subject(selected: Self.publishedVoice)
		try lifecycle.restoreVoice(Self.usersVoice)
		#expect(store.selectedVoice() == Self.usersVoice)

		store.rejectsWrites = true
		#expect(throws: ProviderError.self) { try lifecycle.restoreVoice("com.apple.something.else") }
	}
}
