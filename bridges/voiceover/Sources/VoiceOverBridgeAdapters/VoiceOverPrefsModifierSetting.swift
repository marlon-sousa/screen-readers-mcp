// ROLE: adapter implementing the ReaderModifierSetting port: the key VoiceOver records its modifier under, its three values, and what an absent key means.
// BUILT BY: Wiring, once per process.
// USED BY: the PressGesture handler, through the port.
// `SCRKeysToUseForVOModifier` is undocumented, read out of the `ScreenReader` framework on macOS 15; `scripts/voiceover_vo_modifier.sh` reads the same values from the same files.
// An absent key in a readable file is the Control-Option default; an unreadable file is `unknown`, never a default to press keys on.
// A value not listed here is `unknown`, never a guess.

import Foundation
import VoiceOverBridgeDomain

public final class VoiceOverPrefsModifierSetting: ReaderModifierSetting {
	static let preferencesKey = "SCRKeysToUseForVOModifier"

	static let values: [String: ModifierSetting] = [
		"SCRVOModifierControlOption": .controlOption,
		"SCRVOModifierCapsLock": .capsLock,
		"SCRVOModifierControlOptionOrCapsLock": .controlOptionOrCapsLock,
	]

	private let reader: any PlistReader
	private let home: String

	public init(reader: any PlistReader, home: String) {
		self.reader = reader
		self.home = home
	}

	public func modifier() -> ModifierSetting {
		// The first readable file decides, newest first: an upgraded machine's older file may hold a stale choice VoiceOver no longer reads.
		for path in VoiceOverPreferencesFile.candidates(home: home) {
			guard let preferences = reader.read(at: path) else { continue }
			guard let recorded = preferences[VoiceOverPrefsModifierSetting.preferencesKey] else {
				return .controlOption
			}
			guard let text = recorded as? String,
				let known = VoiceOverPrefsModifierSetting.values[text]
			else {
				return .unknown
			}
			return known
		}
		return .unknown
	}
}
