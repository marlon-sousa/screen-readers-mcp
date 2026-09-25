// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/Wallclock.swift.

import Foundation
import Testing

@testable import VoiceOverBridgeDomain

@Suite("Wallclock")
struct WallclockTests {
	@Test("zero renders as nothing at all, never as 1970")
	func zeroIsEmpty() {
		#expect(Wallclock.format(0) == "")
	}

	@Test("a stamp is `YYYY-MM-DD HH:MM:SS.mmm` -- the transcript's shape, not ISO 8601")
	func theShape() throws {
		let rendered = Wallclock.format(1_700_000_000.5)
		let pattern = try Regex(#"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}$"#)
		#expect(rendered.wholeMatch(of: pattern) != nil, "unexpected shape: \(rendered)")
		#expect(!rendered.contains("T"))
	}

	@Test("milliseconds are kept and nothing finer is invented")
	func resolution() {
		#expect(Wallclock.format(1_700_000_000.123).hasSuffix(".123"))
		#expect(Wallclock.format(1_700_000_000.0).hasSuffix(".000"))
	}

	@Test("it renders the machine's own time zone, which is the transcript's")
	func localTime() {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
		let epoch = 1_700_000_042.75
		#expect(Wallclock.format(epoch) == formatter.string(from: Date(timeIntervalSince1970: epoch)))
	}

	@Test("two stamps subtract, which is the measurement the field exists for")
	func stampsAreOrdered() {
		#expect(Wallclock.format(1_700_000_000) < Wallclock.format(1_700_000_001))
	}
}
