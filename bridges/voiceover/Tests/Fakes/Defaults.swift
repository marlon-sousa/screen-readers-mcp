// A hand-written stateful fake for the Defaults adapter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/Defaults.swift.
//
// An in-memory store, so the settings adapter is tested without writing a
// preference on the developer's machine. It keeps values as `Any` and hands them
// back through the typed readers, which is what lets a test store a value of the
// WRONG type -- an older build's connection mode, a hand-edited port -- and
// assert that the adapter falls back to the shipped default rather than
// propagating it.

import VoiceOverBridgeAdapters

public final class FakeDefaults: Defaults {
	public var values: [String: Any] = [:]

	public init(_ values: [String: Any] = [:]) {
		self.values = values
	}

	public func string(_ key: String) -> String? { values[key] as? String }

	public func integer(_ key: String) -> Int? { values[key] as? Int }

	public func boolean(_ key: String) -> Bool? { values[key] as? Bool }

	public func set(_ key: String, _ value: String) { values[key] = value }

	public func set(_ key: String, _ value: Int) { values[key] = value }

	public func set(_ key: String, _ value: Bool) { values[key] = value }
}
