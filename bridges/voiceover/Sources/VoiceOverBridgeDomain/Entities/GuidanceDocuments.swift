// ROLE: entity, composes the `getGuidance` document: VoiceOver's common section plus the persona's.
// USED BY: the GetGuidance controller and the Hello handler.
// DEPENDS ON: the .md files in Documents/, and nothing else.
// `Bundle.module` is not found automatically inside a script-assembled .app: the resource bundle
// must be copied into Contents/Resources, or this traps at run time.

import Foundation

public enum GuidanceDocuments {
	static let common = "common"

	/// One document per persona the server can declare; an absent value is not an error.
	static let sections = [
		"user": "user",
		"validator": "validator",
		"expert": "expert",
	]

	/// What an unrecognised persona gets: an explanation of what it is missing.
	static let unknown = "unknown"

	/// `recognised == false` is an ordinary outcome, never an error; an empty persona takes the same path.
	public static func guidance(for persona: String) throws -> (text: String, recognised: Bool) {
		let section = sections[persona]
		let text = try read(common) + "\n" + read(section ?? unknown)
		return (text, section != nil)
	}

	/// `.copy` in Package.swift nests the files under this directory, so a lookup at the bundle root
	/// finds nothing.
	static let directory = "Documents"

	static func read(_ name: String) throws -> String {
		guard
			let url = Bundle.module.url(
				forResource: name, withExtension: "md", subdirectory: directory)
		else {
			throw GuidanceDocumentMissing(
				name: name,
				reason: "it is not in the resource bundle this build was assembled with")
		}
		do {
			return try String(contentsOf: url, encoding: .utf8)
		} catch {
			throw GuidanceDocumentMissing(name: name, reason: "it could not be read: \(error)")
		}
	}
}

/// A guidance document this build should carry and does not; `reason` tells a missing resource
/// from an undecodable file.
public struct GuidanceDocumentMissing: Error, Equatable, CustomStringConvertible {
	public let name: String
	public let reason: String

	public init(name: String, reason: String) {
		self.name = name
		self.reason = reason
	}

	public var description: String {
		"the bridge's guidance document '\(name).md' is missing: \(reason)"
	}
}
