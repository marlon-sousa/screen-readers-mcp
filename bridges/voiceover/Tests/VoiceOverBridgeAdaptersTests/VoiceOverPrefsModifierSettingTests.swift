// Mirrors Sources/VoiceOverBridgeAdapters/VoiceOverPrefsModifierSetting.swift.

import Fakes
import Testing
import VoiceOverBridgeDomain

@testable import VoiceOverBridgeAdapters

@Suite("VoiceOverPrefsModifierSetting")
struct VoiceOverPrefsModifierSettingTests {
	private let home = "/Users/somebody"

	private func setting(_ reader: FakePlistReader) -> VoiceOverPrefsModifierSetting {
		VoiceOverPrefsModifierSetting(reader: reader, home: home)
	}

	private var current: String { VoiceOverPreferencesFile.current(home: "/Users/somebody") }
	private var legacy: String { VoiceOverPreferencesFile.legacy(home: "/Users/somebody") }

	@Test("A READABLE FILE THAT DOES NOT MENTION IT IS THE DEFAULT, not an unknown")
	func silenceIsTheDefault() {
		let reader = FakePlistReader()
		reader.plists[current] = ["SomethingElse": 1]
		#expect(setting(reader).modifier() == .controlOption)
	}

	@Test("each of the three values VoiceOver writes is read as itself")
	func theThreeValues() {
		for (written, expected): (String, ModifierSetting) in [
			("SCRVOModifierControlOption", .controlOption),
			("SCRVOModifierCapsLock", .capsLock),
			("SCRVOModifierControlOptionOrCapsLock", .controlOptionOrCapsLock),
		] {
			let reader = FakePlistReader()
			reader.plists[current] = ["SCRKeysToUseForVOModifier": written]
			#expect(setting(reader).modifier() == expected)
		}
	}

	@Test("A FILE THAT COULD NOT BE READ IS `unknown`, AND NOT THE DEFAULT")
	func unreadableIsUnknown() {
		#expect(setting(FakePlistReader()).modifier() == .unknown)
	}

	@Test("a value this bridge does not know is `unknown`, not a guess")
	func anUnknownValueIsUnknown() {
		let reader = FakePlistReader()
		reader.plists[current] = ["SCRKeysToUseForVOModifier": "SCRVOModifierSomethingNew"]
		#expect(setting(reader).modifier() == .unknown)
	}

	@Test("a value of the wrong TYPE is unknown too")
	func aNonStringValueIsUnknown() {
		let reader = FakePlistReader()
		reader.plists[current] = ["SCRKeysToUseForVOModifier": 1]
		#expect(setting(reader).modifier() == .unknown)
	}

	@Test("THE PRE-SEQUOIA LOCATION IS READ ONLY WHEN THE CURRENT ONE IS NOT THERE")
	func theNewerFileWins() {
		let reader = FakePlistReader()
		reader.plists[current] = ["SomethingElse": 1]
		reader.plists[legacy] = ["SCRKeysToUseForVOModifier": "SCRVOModifierCapsLock"]
		#expect(setting(reader).modifier() == .controlOption)
	}

	@Test("and it IS read on a machine that never moved")
	func theOlderFileIsStillRead() {
		let reader = FakePlistReader()
		reader.plists[legacy] = ["SCRKeysToUseForVOModifier": "SCRVOModifierCapsLock"]
		#expect(setting(reader).modifier() == .capsLock)
	}

	@Test("it reads the file `VoiceOverPreferencesFile` names, and does not carry its own copy")
	func oneIdeaOfWhereTheFileIs() {
		#expect(VoiceOverPreferencesFile.current(home: home) == current)
	}
}
