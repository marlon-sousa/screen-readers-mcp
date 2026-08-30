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
// REGISTRATION IS NOT PERFORMED HERE, and that is a deliberate absence rather
// than an omission: re-registering only takes effect after the reader restarts
// (finding 6), and restarting a blind person's screen reader is not a decision a
// handshake may take. The recovery is REPORTED, by name, with its order --
// `lsregister -f` first and `pluginkit -a` second, because the first alone was
// measured not to be enough (spec 0041, C1) -- and 13.10's dialog is where a
// human drives it.

import Foundation
import VoiceOverBridgeDomain

public final class PluginKitProviderLifecycle: ProviderLifecycle {
	static let pluginKitTool = "/usr/bin/pluginkit"
	/// The extension point every speech provider registers against, read out of
	/// Apple's own SiriAUSP.appex rather than recalled (spec 0046, part 3).
	static let speechExtensionPoint = "com.apple.AudioUnit-Speech"

	private let runner: any ProcessRunner
	private let published: any PublishedVoices
	private let store: any VoiceStore
	private let extensionBundleID: String
	private let voiceIdentifierSuffix: String

	/// `extensionBundleID` is what pluginkit lists; `voiceIdentifierSuffix` is
	/// what the audio unit declares, and what the published identifier ENDS with.
	/// Both are passed in rather than read from a constant here, so this class
	/// stays the place that knows what an answer means and not the place that
	/// knows what we are called.
	public init(
		runner: any ProcessRunner,
		published: any PublishedVoices,
		store: any VoiceStore,
		extensionBundleID: String,
		voiceIdentifierSuffix: String
	) {
		self.runner = runner
		self.published = published
		self.store = store
		self.extensionBundleID = extensionBundleID
		self.voiceIdentifierSuffix = voiceIdentifierSuffix
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
