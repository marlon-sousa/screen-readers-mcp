// ROLE: entity, the wire version this binding speaks; scripts/drift.py reads the number from this file.

public enum ProtocolVersion {
	public static let current = 1

	public static let supported: Set<Int> = [current]

	public static func supports(_ version: Int) -> Bool {
		supported.contains(version)
	}
}
