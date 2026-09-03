// Unit tests for VoiceOverPrefsModifierSetting, mirroring
// Sources/VoiceOverBridgeAdapters/VoiceOverPrefsModifierSetting.swift.
//
// WHAT IS UNDER TEST IS THE MEANING OF WHAT WAS READ, not the reading: the leaf
// beneath it does `NSDictionary(contentsOfFile:)` and nothing else, and the
// decisions -- which file wins, what an absent key means, what an unrecognised
// value means -- are all here.
//
// THE ABSENT-KEY CASE IS THE ONE THAT MATTERS. VoiceOver records only deviations
// from its defaults, so a readable file that never mentions the modifier is a
// machine on Control-Option. Getting that backwards would refuse `vo+m` on every
// ordinary Mac.

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
		// The rule the whole adapter turns on: the reader records deviations only.
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
		// "I could not look" and "it is at its default" are different facts, and
		// the entity presses keys on one of them.
		#expect(setting(FakePlistReader()).modifier() == .unknown)
	}

	@Test("a value this bridge does not know is `unknown`, not a guess")
	func anUnknownValueIsUnknown() {
		// A future macOS may add a fourth choice. Reporting it as Control-Option
		// would press two keys that are not the modifier on that machine.
		let reader = FakePlistReader()
		reader.plists[current] = ["SCRKeysToUseForVOModifier": "SCRVOModifierSomethingNew"]
		#expect(setting(reader).modifier() == .unknown)
	}

	@Test("a value of the wrong TYPE is unknown too")
	func aNonStringValueIsUnknown() {
		// The plist type trap that made a correct-looking voice write vanish (spec
		// 0047, finding 17), in the direction that is safe here: this file refuses
		// rather than coercing, because there is no spelling of a modifier choice
		// that is a number.
		let reader = FakePlistReader()
		reader.plists[current] = ["SCRKeysToUseForVOModifier": 1]
		#expect(setting(reader).modifier() == .unknown)
	}

	@Test("THE PRE-SEQUOIA LOCATION IS READ ONLY WHEN THE CURRENT ONE IS NOT THERE")
	func theNewerFileWins() {
		// Sequoia MOVED the file rather than adding a second one, so a machine that
		// was upgraded can carry a stale copy of the old one -- and the reader is
		// no longer reading it. The first file that can be READ decides, not the
		// first that mentions the key.
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
		// Two adapters each carrying their own copy of a path is how two adapters
		// come to disagree about where a file is, which is why
		// `VoiceOverPreferencesFile` exists at all. It HAD two readers until 13.31
		// -- the scripting setting was the other, and this assertion compared them
		// directly. One reader is not a reason to inline the derivation: the next
		// entry that reads one of VoiceOver's own preferences is the reason the
		// file exists.
		#expect(VoiceOverPreferencesFile.current(home: home) == current)
	}
}
