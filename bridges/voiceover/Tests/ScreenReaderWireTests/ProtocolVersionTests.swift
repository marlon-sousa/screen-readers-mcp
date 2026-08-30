// Mirrors Sources/ScreenReaderWire/ProtocolVersion.swift.

import Testing

@testable import ScreenReaderWire

@Suite("ProtocolVersion")
struct ProtocolVersionTests {
	@Test("the binding announces the version the published schema declares")
	func currentIsOne() {
		// specs/wire/v1/schema.json's `protocolVersion`. scripts/drift.py is what
		// keeps the two equal; this is the assertion from the Swift side.
		#expect(ProtocolVersion.current == 1)
	}

	@Test("a peer on the same version is talked to, and any other is not")
	func supportsExactlyTheCurrentVersion() {
		#expect(ProtocolVersion.supports(1))
		#expect(!ProtocolVersion.supports(2))
		#expect(!ProtocolVersion.supports(0))
	}

	@Test("support is a set, so accepting a second version stays a change to data")
	func supportedIsASet() {
		#expect(ProtocolVersion.supported == [ProtocolVersion.current])
	}
}
