// Mirrors Sources/VoiceOverBridgeAdapters/VoiceOverPrefsScriptingSetting.swift.
//
// IT MUST AGREE WITH `scripts/voiceover_channels.sh`, AND THAT IS THE POINT OF
// THE FIRST TEST. That script is the instrument this repository already has for
// "is AppleScript control of VoiceOver on?", and it reads exactly two locations:
// the Group Container `default.plist` key `SCREnableAppleScript`, and the legacy
// marker `/private/var/db/Accessibility/.VoiceOverAppleScriptEnabled`. A second
// probe that read somewhere else would answer a different question while looking
// like the same one, so the paths are asserted rather than assumed.
//
// THE OTHER HALF IS THE THIRD ANSWER. "I looked and found nothing" and "I could
// not look" are different, and only one of them should send a human to VoiceOver
// Utility.

import Fakes
import Testing
import VoiceOverBridgeDomain

@testable import VoiceOverBridgeAdapters

@Suite("VoiceOverPrefsScriptingSetting")
struct VoiceOverPrefsScriptingSettingTests {
	private let home = "/Users/tester"
	private var preferences: String {
		VoiceOverPrefsScriptingSetting.preferencesPath(home: home)
	}
	private let marker = VoiceOverPrefsScriptingSetting.legacyMarkerPath

	private func setting(_ reader: FakePlistReader) -> VoiceOverPrefsScriptingSetting {
		VoiceOverPrefsScriptingSetting(reader: reader, home: home)
	}

	@Test("IT READS THE TWO LOCATIONS `scripts/voiceover_channels.sh` READS, and no others")
	func theTwoLocations() {
		// Sequoia ADDED the first; it did not replace the second. The probe records
		// that, and so does this.
		let reader = FakePlistReader()
		_ = setting(reader).scripting()
		#expect(reader.existenceChecks == [marker])
		#expect(reader.reads == [preferences])
		#expect(
			preferences
				== "/Users/tester/Library/Group Containers/group.com.apple.VoiceOver/Library/Preferences"
				+ "/com.apple.VoiceOver4/default.plist")
		#expect(marker == "/private/var/db/Accessibility/.VoiceOverAppleScriptEnabled")
	}

	@Test("the preference key says yes")
	func thePreferenceSaysYes() {
		let reader = FakePlistReader()
		reader.plists[preferences] = ["SCREnableAppleScript": true]
		#expect(setting(reader).scripting() == .enabled)
	}

	@Test("EITHER LOCATION IS ENOUGH: an upgraded machine can carry only the old one")
	func theLegacyMarkerIsEnough() {
		let reader = FakePlistReader()
		reader.files.insert(marker)
		#expect(setting(reader).scripting() == .enabled)
	}

	@Test("a readable preferences file that does not mention it means OFF")
	func silenceInAReadableFileIsOff() {
		// VoiceOver records only deviations from its defaults, and this switch ships
		// off -- so a file we could read and that does not mention it IS off.
		let reader = FakePlistReader()
		reader.plists[preferences] = ["SCRSomethingElse": true]
		#expect(setting(reader).scripting() == .disabled)
	}

	@Test("the key set to false means off")
	func falseIsOff() {
		let reader = FakePlistReader()
		reader.plists[preferences] = ["SCREnableAppleScript": false]
		#expect(setting(reader).scripting() == .disabled)
	}

	@Test("NEITHER LOCATION READABLE IS `unknown`, NOT `disabled`")
	func nothingReadableIsUnknown() {
		// The honest third answer: reporting `disabled` here would send a human to
		// fix a switch that may already be on.
		#expect(setting(FakePlistReader()).scripting() == .unknown)
	}

	@Test("a value written as a STRING still counts, which is spec 0047's type trap")
	func theTypeTrap() {
		// `defaults write` with an old-style plist literal makes every value a
		// string. That is what made a correct-looking voice write vanish (finding
		// 17); here it would report a machine with the switch on as off.
		for written in ["1", "true", "YES"] {
			let reader = FakePlistReader()
			reader.plists[preferences] = ["SCREnableAppleScript": written]
			#expect(setting(reader).scripting() == .enabled, "\(written) should read as on")
		}
		let reader = FakePlistReader()
		reader.plists[preferences] = ["SCREnableAppleScript": "0"]
		#expect(setting(reader).scripting() == .disabled)
	}

	@Test("it is read fresh every time, so a human who fixes the switch sees it change")
	func itIsNotCached() {
		let reader = FakePlistReader()
		let subject = setting(reader)
		#expect(subject.scripting() == .unknown)
		reader.files.insert(marker)
		#expect(subject.scripting() == .enabled)
	}
}
