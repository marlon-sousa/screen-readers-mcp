// ROLE: adapter -- IMPLEMENTS the ReaderModifierSetting domain port. It knows
// the key VoiceOver records its modifier choice under, the three values that key
// can hold, and what an ABSENT key means.
//
// BUILT BY: Wiring, once per process. USED BY: the PressGesture handler, through
// the port. HOLDS: the PlistReader seam, and VoiceOverPreferencesFile for the
// paths.
//
// THE KEY IS PUBLISHED NOWHERE, AND WAS EXTRACTED FROM THE MACHINE. Apple's own
// documentation names the three choices as they appear in VoiceOver Utility and
// never the preference behind them; no third party publishes it either. It was
// read out of the dyld shared cache on 2026-09-02 -- the `ScreenReader`
// framework's binary is not on disk as a file -- and then confirmed against a
// machine at its default. Spec 0052 §2.1. `scripts/voiceover_vo_modifier.sh`
// prints the same three values from the same files, so a human diagnosing a
// machine and this adapter cannot reach different conclusions about it.
//
// AN ABSENT KEY IS THE DEFAULT, AND AN UNREADABLE FILE IS NOT. VoiceOver records
// only DEVIATIONS from its defaults, so a readable file that does not mention the
// key is a machine on Control-Option -- which is exactly the rule
// VoiceOverPrefsScriptingSetting encodes for `SCREnableAppleScript`, in the
// opposite direction (that switch ships OFF, so silence there means off). "I
// looked and found nothing" and "I could not look" are different answers, and
// only one of them may be acted on by pressing keys.
//
// AND A VALUE THIS FILE DOES NOT KNOW IS `unknown`, NOT A GUESS. A future macOS
// may add a fourth choice. Reporting it as Control-Option would press two keys
// that are not the modifier on that machine, with total confidence and nothing
// anywhere to see -- the failure shape this lane keeps paying for.
//
// IT NEVER WRITES. Nothing here sets somebody's modifier: it is theirs, it is
// changed in VoiceOver Utility, and a bridge that rewrote VoiceOver's preferences
// behind the reader's back is the manoeuvre that destroyed the maintainer's
// stored voice settings once already (spec 0047, finding 17).

import Foundation
import VoiceOverBridgeDomain

public final class VoiceOverPrefsModifierSetting: ReaderModifierSetting {
	/// The key VoiceOver records a modifier choice under. Absent means default.
	static let preferencesKey = "SCRKeysToUseForVOModifier"

	/// The three values that key can hold, as VoiceOver spells them.
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
		// NEWEST LOCATION FIRST, and the first file that can be READ decides --
		// not the first one that mentions the key. A machine upgraded to Sequoia
		// can still carry the pre-Sequoia file with a stale choice in it, and the
		// reader is no longer reading that one.
		for path in VoiceOverPreferencesFile.candidates(home: home) {
			guard let preferences = reader.read(at: path) else { continue }
			guard let recorded = preferences[VoiceOverPrefsModifierSetting.preferencesKey] else {
				// Readable, and the choice is not mentioned: it is at its default.
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
