// ROLE: adapter implementing the VoiceStore seam by rewriting the preference that decides which voice VoiceOver speaks with.
// BUILT BY: Wiring.
// USED BY: PluginKitProviderLifecycle, through the seam.
// On macOS 15 VoiceOver's voice lives in `com.apple.SpeakSelection`, key `VoiceOverDefaultVoiceSelections`, an array alternating a language tag with a record, so records are found by `_type`.
// Round-tripped through `defaults export` and `import`, because a `defaults write` literal makes `pitch` and `rate` strings, and VoiceOver on macOS 15 then silently rejects the record and overwrites the key.
// `scripts/voiceover_voice.py` is the same mechanism, run against a live reader; if the two disagree, trust the script.
// Does not confirm the write; PluginKitProviderLifecycle does.

import Foundation

public final class SpeakSelectionVoiceStore: VoiceStore {
	/// Not `com.apple.VoiceOver4`, which holds no voice.
	static let domain = "com.apple.SpeakSelection"
	static let key = "VoiceOverDefaultVoiceSelections"
	/// Only records of this type are rewritten; anything else in the array is left as it was.
	static let entryType = "Speech.VoiceSelection"
	static let defaultsTool = "/usr/bin/defaults"

	private let runner: any ProcessRunner

	public init(runner: any ProcessRunner) {
		self.runner = runner
	}

	public func selectedVoice() -> String? {
		guard let selections = try? read().selections else { return nil }
		// The first record wins when several languages are configured.
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

	/// Mutable containers, so the returned records are the ones inside `plist` and rewriting them rewrites it.
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
