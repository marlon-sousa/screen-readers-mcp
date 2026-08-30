// ROLE: adapter -- IMPLEMENTS the VoiceStore seam by reading and rewriting the
// one preference that decides which voice VoiceOver speaks with.
//
// BUILT BY: Wiring. USED BY: PluginKitProviderLifecycle, through the seam.
// HOLDS: a ProcessRunner, because the preference is reached through `defaults`
// and this class decides everything except how to launch a tool.
//
// WHERE THE VOICE ACTUALLY LIVES, because an evening was spent finding out and
// the answer is counter-intuitive enough to be worth repeating here (spec 0047,
// findings 10 and 16). NOT in VoiceOver's own preferences, and not in its group
// container: those hold timestamps and runtime state, and VoiceOver's own writes
// during a voice change go to /dev/null. The store is the SYSTEM SPEECH domain,
// one namespace over:
//
//     ~/Library/Preferences/com.apple.SpeakSelection.plist
//         VoiceOverDefaultVoiceSelections = ( "<lang>", Speech.VoiceSelection )
//
// The array alternates a language tag with a record, so the records are found by
// their own `_type` rather than by position -- an index would break the first
// time a machine has two languages configured.
//
// WHY export -> modify -> import, AND NOT `defaults write`. An old-style plist
// literal makes every value a STRING. Written that way, `pitch` and `rate`
// arrive as text where reals are expected; VoiceOver SILENTLY REJECTS the
// record, falls back to the system default voice, AND THEN REWRITES THE KEY with
// its own choice -- so the evidence of the write is gone before you look, and it
// presents as "writing the preference does nothing". That wrong conclusion is
// recorded in spec 0047 as finding 2 and was only overturned by finding 17.
// PropertyListSerialization round-trips types, which is the whole reason this
// class parses rather than formats.
//
// `scripts/voiceover_voice.py` IS THE SAME MECHANISM AS A TOOL, and it is the
// instrument the finding was made with. If this file and that script ever
// disagree about what to write, the script is the one that has been run against
// a live reader.
//
// IT DOES NOT CONFIRM ITS OWN WRITE, deliberately: confirming means knowing
// which voice is ours, which is PluginKitProviderLifecycle's business and not a
// preference domain's. This class writes what it was asked to write and says
// whether the write itself failed.

import Foundation

public final class SpeakSelectionVoiceStore: VoiceStore {
	/// The system speech domain. NOT `com.apple.VoiceOver4`, which holds no voice
	/// at all -- see the header.
	static let domain = "com.apple.SpeakSelection"
	static let key = "VoiceOverDefaultVoiceSelections"
	/// What the records we may rewrite call themselves. Anything else in that
	/// array is left exactly as it was.
	static let entryType = "Speech.VoiceSelection"
	static let defaultsTool = "/usr/bin/defaults"

	private let runner: any ProcessRunner

	public init(runner: any ProcessRunner) {
		self.runner = runner
	}

	public func selectedVoice() -> String? {
		guard let selections = try? read().selections else { return nil }
		// The FIRST record wins when a machine has several languages configured.
		// A machine with two is a machine with two answers, and this port asks for
		// one -- the alternative would be a list nobody up the stack can act on.
		return selections.compactMap { $0["voiceId"] as? String }.first
	}

	public func select(_ identifier: String) throws {
		let (plist, selections) = try read()
		guard !selections.isEmpty else {
			throw VoiceStoreError(
				"\(SpeakSelectionVoiceStore.domain) has no \(SpeakSelectionVoiceStore.entryType) record to "
					+ "rewrite: a voice has to be chosen once, by hand, before there is a selection to change")
		}
		for record in selections {
			record["voiceId"] = identifier
		}
		let data = try PropertyListSerialization.data(
			fromPropertyList: plist, format: .xml, options: 0)
		let result = try runner.run(
			SpeakSelectionVoiceStore.defaultsTool,
			["import", SpeakSelectionVoiceStore.domain, "-"],
			stdin: data
		)
		guard result.succeeded else {
			throw VoiceStoreError("defaults import failed (status \(result.status)): \(result.standardError)")
		}
	}

	/// The whole domain, plus the records inside it that carry a voice.
	///
	/// Mutable containers, so the records handed back are the ones inside the
	/// plist rather than copies of them -- which is what makes "modify, then
	/// serialize the same object" true rather than merely plausible.
	private func read() throws -> (plist: Any, selections: [NSMutableDictionary]) {
		let result = try runner.run(
			SpeakSelectionVoiceStore.defaultsTool,
			["export", SpeakSelectionVoiceStore.domain, "-"]
		)
		guard result.succeeded else {
			throw VoiceStoreError("defaults export failed (status \(result.status)): \(result.standardError)")
		}
		var format = PropertyListSerialization.PropertyListFormat.xml
		let plist: Any
		do {
			plist = try PropertyListSerialization.propertyList(
				from: result.standardOutput, options: [.mutableContainersAndLeaves], format: &format)
		} catch {
			throw VoiceStoreError("\(SpeakSelectionVoiceStore.domain) did not parse as a plist: \(error)")
		}
		guard let root = plist as? NSDictionary,
			let entries = root[SpeakSelectionVoiceStore.key] as? NSArray
		else {
			throw VoiceStoreError(
				"\(SpeakSelectionVoiceStore.domain) has no \(SpeakSelectionVoiceStore.key)")
		}
		let selections = entries.compactMap { entry -> NSMutableDictionary? in
			guard let record = entry as? NSMutableDictionary,
				record["_type"] as? String == SpeakSelectionVoiceStore.entryType
			else { return nil }
			return record
		}
		return (plist, selections)
	}
}
