// ROLE: adapter -- IMPLEMENTS the ProviderLifecycle domain port. THE ONLY PLACE
// THAT KNOWS WHAT THE SYSTEM'S ANSWERS MEAN about the capture voice.
//
// BUILT BY: Wiring. USED BY: the Hello handler, the Session's teardown, and the
// two waiting speech handlers.
// HOLDS: a ProcessRunner (pluginkit), a PublishedVoices (the machine's voice
// list) and a VoiceStore (the preference VoiceOver reads) -- three seams, because
// the state machine is assembled from three INDEPENDENT signals and collapsing
// any two of them would collapse two different diagnoses into one.
//
// THE THREE SIGNALS, AND WHY EACH IS THE ONE IT IS:
//
//  * REGISTERED comes from `pluginkit -m -p com.apple.AudioUnit-Speech -v`,
//    which spec 0047's finding 18 names the AUTHORITATIVE registration signal.
//    Never `say -v '?'`, which advertised the voice from a stale cache for an
//    hour after the extension was unregistered.
//  * PUBLISHED comes from the machine's own voice list, matched BY SUFFIX --
//    never by the identifier the audio unit declared, because the system
//    publishes ours prefixed with the extension's bundle id (spec 0041, A1). The
//    match also DISCOVERS the string to write: whatever the system published is
//    what the preference has to say.
//  * SELECTED comes from the system speech domain, through the VoiceStore seam.
//
// AND THE ONE IT CANNOT HAVE: whether VOICEOVER offers the voice. It has no list
// to ask, AppleScript exposes none, and finding 6 measured the two disagreeing
// invisibly. So `published` names that condition rather than assuming its way
// past it -- which is the whole reason ProviderState has five states and not a
// boolean.
//
// REGISTRATION IS PERFORMED HERE SINCE 13.20, AND THIS PARAGRAPH USED TO SAY IT
// WAS NOT. The old text called the absence deliberate, on the grounds that
// re-registering only takes effect after the reader restarts (finding 6) and
// that no handshake may restart a blind person's screen reader. That is right
// about the RESTART and was over-applied to the REGISTRATION: registering is two
// silent subprocesses that change nothing a running reader can see. So this
// class does it, and the restart is still reported rather than taken.
//
// THE ORDER IS THE CONTRACT: `lsregister -f` on the .app FIRST and `pluginkit
// -a` on the .appex SECOND, because the first alone was measured not to be
// enough (spec 0041, C1).
//
// AND IT IS CONFIRMED BY POLLING, NOT BY AN EXIT STATUS. MEASURED 2026-08-31:
// `pluginkit -a` hands the work to `pkd` and returns, so an immediate re-read
// reports failure on a registration that worked. A false alarm here is worse
// than no check at all -- it sends a human to redo something already done -- so
// the confirmation is `isRegistered()` polled over a window, on the injected
// Clock so a test pays none of it.
//
// THE PATHS ARE NOT DERIVED HERE. This class knows identifiers; Wiring knows
// where a bundle is (see CaptureBundle). Given none, `register()` is a NAMED
// FAILURE that carries both commands so a human can run them by hand -- which is
// strictly better than guessing at a path and reporting success for an
// `lsregister` that registered nothing.
//
// THERE IS NO `unregister()`. See the port: SESSION state is restored at
// teardown, MACHINE state is not.

import Foundation
import VoiceOverBridgeDomain

public final class PluginKitProviderLifecycle: ProviderLifecycle {
	static let pluginKitTool = "/usr/bin/pluginkit"
	/// The extension point every speech provider registers against, read out of
	/// Apple's own SiriAUSP.appex rather than recalled (spec 0046, part 3).
	static let speechExtensionPoint = "com.apple.AudioUnit-Speech"

	/// Where LaunchServices lives. Absolute, like every other tool this bridge
	/// runs, so nothing depends on the caller's PATH.
	static let launchServicesTool =
		"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework"
		+ "/Support/lsregister"

	/// How long `register()` waits for pkd to catch up before calling it a
	/// failure. Wide, because a false negative here is the expensive direction.
	static let registrationConfirmationSeconds: Double = 5.0

	/// How long the system is given to PUBLISH a newly registered voice.
	///
	/// FAR WIDER THAN THE REGISTRATION WINDOW, and deliberately so. `pluginkit`
	/// hands its work to `pkd` and the listing catches up in well under a second;
	/// publishing is a different mechanism on a different schedule -- this bridge's
	/// own README has said "roughly every 30 seconds" since 13.4, and
	/// `CaptureProbe refresh` waits 3 seconds and often has to be run twice. A
	/// window that was too tight here would fail a handshake on a machine that was
	/// about to work, which is exactly the failure 13.20 exists to remove.
	///
	/// IT IS PAID ONLY AFTER A REGISTRATION, which in practice means only by
	/// whoever has just run `poe build`. An ordinary handshake never enters this
	/// path at all.
	static let publicationSeconds: Double = 45.0

	/// How often it re-asks inside that window.
	static let registrationPollInterval: Double = 0.25

	private let runner: any ProcessRunner
	private let published: any PublishedVoices
	private let store: any VoiceStore
	private let extensionBundleID: String
	private let voiceIdentifierSuffix: String
	private let bundlePaths: CaptureBundlePaths?
	private let clock: any Clock

	/// `extensionBundleID` is what pluginkit lists; `voiceIdentifierSuffix` is
	/// what the audio unit declares, and what the published identifier ENDS with.
	/// Both are passed in rather than read from a constant here, so this class
	/// stays the place that knows what an answer means and not the place that
	/// knows what we are called.
	/// `bundlePaths` is what `register()` points the two tools at, and nil is a
	/// legitimate answer: a process that is not running out of the assembled
	/// bundle and cannot find one beside the package has nothing truthful to
	/// register. The `Clock` is the registration poll's, injected for the reason
	/// every clock in this repo is -- so its test costs microseconds rather than
	/// five real seconds.
	public init(
		runner: any ProcessRunner,
		published: any PublishedVoices,
		store: any VoiceStore,
		extensionBundleID: String,
		voiceIdentifierSuffix: String,
		bundlePaths: CaptureBundlePaths? = nil,
		clock: any Clock = RealClock()
	) {
		self.runner = runner
		self.published = published
		self.store = store
		self.extensionBundleID = extensionBundleID
		self.voiceIdentifierSuffix = voiceIdentifierSuffix
		self.bundlePaths = bundlePaths
		self.clock = clock
	}

	// -- the state machine ----------------------------------------------------

	public func state() -> ProviderState {
		guard isRegistered() else { return .notRegistered }
		guard publishedCaptureVoice() != nil else { return .registered }
		guard selectedVoice()?.isCaptureVoice == true else { return .published }
		// `capturing` is never claimed here: utterances arriving is the only
		// evidence of it, and this class cannot see the feed. Whoever holds the
		// buffer promotes it -- see ProviderState.observing(captured:).
		return .selected
	}

	public func selectedVoice() -> SelectedVoice? {
		guard let identifier = store.selectedVoice() else { return nil }
		return SelectedVoice(identifier: identifier, isCaptureVoice: isOurs(identifier))
	}

	/// THE SAME LIST `publishedCaptureVoice()` MATCHES AGAINST, read a second time
	/// rather than duplicated: this bridge has one authority on "does this
	/// identifier exist here", so the answer it gives about the user's voice cannot
	/// disagree with the answer it gives about ours. See the port for what a `true`
	/// does and does not claim.
	public func systemPublishesVoice(_ identifier: String) -> Bool {
		published.identifiers().contains(identifier)
	}

	public func register() throws {
		guard let paths = bundlePaths else {
			throw ProviderError(
				"this bridge does not know where its own app bundle is, so it cannot register the "
					+ "capture voice's extension. Run these two, in this order: "
					+ "\(Self.launchServicesTool) -f <path to \(captureAppName).app> "
					+ "&& /usr/bin/pluginkit -a <that path>/Contents/PlugIns/\(captureExtensionName).appex")
		}
		// THE ORDER IS THE CONTRACT. lsregister first: pluginkit alone was
		// measured not to be enough (spec 0041, C1).
		try run(Self.launchServicesTool, ["-f", paths.app], step: "register the app bundle")
		try run(Self.pluginKitTool, ["-a", paths.appex], step: "add the speech extension")

		// CONFIRMED BY POLLING. pluginkit hands the work to pkd and returns, so
		// the exit status above says nothing about whether the extension is
		// listed yet.
		let deadline = clock.monotonic() + Self.registrationConfirmationSeconds
		while !isRegistered() {
			guard clock.monotonic() < deadline else {
				throw ProviderError(
					"the capture voice's extension was registered and pluginkit still does not list it "
						+ "after \(Int(Self.registrationConfirmationSeconds)) seconds. "
						+ ReaderCondition.providerNotRunning.described)
			}
			clock.sleep(Self.registrationPollInterval)
		}
	}

	/// Ask the system to re-read provider voices, and wait until ours is there.
	///
	/// THE STEP THE VOICE LIST WILL NOT HAPPEN WITHOUT. `CaptureProbe` has called
	/// this since 13.4 and the handshake did not, which cost 13.26's first live
	/// connect: registered, restarted, and the voice had never been published.
	///
	/// REFRESHED ON EVERY POLL, not once before the loop. The call is a REQUEST to
	/// re-read on the system's own schedule, and one that lands while the system is
	/// mid-read is one that changed nothing -- so asking again each time is what
	/// makes the wait converge rather than merely elapse. It is cheap, and
	/// `CaptureProbe`'s having to be run twice by hand is the same observation from
	/// the other end.
	public func publish() throws {
		let deadline = clock.monotonic() + Self.publicationSeconds
		while true {
			published.refresh()
			if publishedCaptureVoice() != nil { return }
			guard clock.monotonic() < deadline else {
				throw ProviderError(
					"the capture voice's extension is registered and the system still does not offer its "
						+ "voice after \(Int(Self.publicationSeconds)) seconds. "
						+ ReaderCondition.providerNotRunning.described)
			}
			clock.sleep(Self.registrationPollInterval)
		}
	}

	/// One registration tool, with its failure named as itself.
	///
	/// A tool that could not be LAUNCHED and one that ran and refused are
	/// different problems with different recoveries, and both are reported as
	/// what they were rather than folded into "registration failed".
	private func run(_ tool: String, _ arguments: [String], step: String) throws {
		let result: ProcessResult
		do {
			result = try runner.run(tool, arguments)
		} catch {
			throw ProviderError("could not run \(tool) to \(step): \(error)")
		}
		guard result.succeeded else {
			let detail = result.standardError.isEmpty ? result.output : result.standardError
			throw ProviderError(
				"\(tool) refused to \(step) (exit \(result.status))"
					+ (detail.isEmpty ? "" : ": \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"))
		}
	}

	public func selectCaptureVoice() throws {
		guard let identifier = publishedCaptureVoice() else {
			throw ProviderError("cannot select the capture voice: " + state().report)
		}
		do {
			try store.select(identifier)
		} catch let failure as VoiceStoreError {
			throw ProviderError("could not write the capture voice: \(failure.description)")
		}
		// CONFIRMED, NEVER ASSUMED. A record VoiceOver rejects is rewritten with
		// its own choice, so a write that failed looks exactly like one that was
		// never made (spec 0047, finding 17). And a voice VoiceOver does not offer
		// is a write that cannot stick at all, which is finding 6 -- so this is
		// where that condition is actually caught.
		guard selectedVoice()?.isCaptureVoice == true else {
			throw ProviderError(
				"the capture voice was written and did not take. "
					+ ReaderCondition.captureVoiceNotOfferedByReader.described)
		}
	}

	public func restoreVoice(_ identifier: String) throws {
		do {
			try store.select(identifier)
		} catch let failure as VoiceStoreError {
			throw ProviderError("could not restore the user's voice: \(failure.description)")
		}
		guard store.selectedVoice() == identifier else {
			throw ProviderError(
				"the user's voice '\(identifier)' was written back and did not take; the reader is "
					+ "still on '\(store.selectedVoice() ?? "<unreadable>")'")
		}
	}

	// -- what the system's answers mean ---------------------------------------

	/// Whether pluginkit lists our extension, and has not been told to disable it.
	///
	/// A line looks like `+    <bundle id>(1.0)\t<uuid>\t<date>\t<path>`, where
	/// the first column is the ENABLEMENT MARKER: `+` for explicitly enabled, a
	/// blank for the default state -- which is what every one of Apple's own
	/// speech providers carries -- and `-` or `!` for disabled. So a blank counts
	/// as registered and only an explicit refusal does not.
	private func isRegistered() -> Bool {
		guard
			let result = try? runner.run(
				PluginKitProviderLifecycle.pluginKitTool,
				["-m", "-p", PluginKitProviderLifecycle.speechExtensionPoint, "-v"]),
			result.succeeded
		else { return false }
		for line in result.output.split(separator: "\n", omittingEmptySubsequences: true) {
			guard let marker = line.first else { continue }
			let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
			let identifier = body.split(separator: "(", maxSplits: 1).first.map(String.init) ?? body
			guard identifier == extensionBundleID else { continue }
			return marker != "-" && marker != "!"
		}
		return false
	}

	/// The identifier the SYSTEM published our voice under, matched by suffix.
	private func publishedCaptureVoice() -> String? {
		published.identifiers().first(where: isOurs)
	}

	private func isOurs(_ identifier: String) -> Bool {
		identifier.hasSuffix(voiceIdentifierSuffix)
	}
}
