// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/Wallclock.swift.
//
// THE FORMAT IS A CONTRACT, not a preference: protocol.md §7.1 states the shape,
// the Python bridge renders the same one, and the value of the field is that a
// stamp pastes into a search of the transcript beside it. So the assertions are
// about the SHAPE and about the two ends of the range, not about a particular
// moment -- the machine's own time zone decides that, and this repo does not
// compare a stamp against a hard-coded local time.

import Foundation
import Testing

@testable import VoiceOverBridgeDomain

@Suite("Wallclock")
struct WallclockTests {
	@Test("zero renders as nothing at all, never as 1970")
	func zeroIsEmpty() {
		// Zero is the buffer's sentinel and the answer for an out-of-range index.
		// It means "no instant was recorded", which an empty string says and a
		// date fifty years ago actively misleads about (spec 0028).
		#expect(Wallclock.format(0) == "")
	}

	@Test("a stamp is `YYYY-MM-DD HH:MM:SS.mmm` -- the transcript's shape, not ISO 8601")
	func theShape() throws {
		let rendered = Wallclock.format(1_700_000_000.5)
		let pattern = try Regex(#"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}$"#)
		#expect(rendered.wholeMatch(of: pattern) != nil, "unexpected shape: \(rendered)")
		// No `T`, no zone suffix: two things an ISO 8601 renderer would add, and
		// either would break the paste-into-the-transcript property.
		#expect(!rendered.contains("T"))
	}

	@Test("milliseconds are kept and nothing finer is invented")
	func resolution() {
		#expect(Wallclock.format(1_700_000_000.123).hasSuffix(".123"))
		#expect(Wallclock.format(1_700_000_000.0).hasSuffix(".000"))
	}

	@Test("it renders the machine's own time zone, which is the transcript's")
	func localTime() {
		// Asserted by construction rather than by a literal: the same instant
		// rendered here and by a formatter in the current zone must agree.
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
		let epoch = 1_700_000_042.75
		#expect(Wallclock.format(epoch) == formatter.string(from: Date(timeIntervalSince1970: epoch)))
	}

	@Test("two stamps subtract, which is the measurement the field exists for")
	func stampsAreOrdered() {
		// spec 0028's motivating case: "X happened promptly after Y". The strings
		// sort chronologically because the shape is big-endian, so an agent can
		// compare them without parsing when it only needs the order.
		#expect(Wallclock.format(1_700_000_000) < Wallclock.format(1_700_000_001))
	}
}
