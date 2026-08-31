// ROLE: entity -- composes the document `getGuidance` returns: VoiceOver's common
// section plus the section for the session's persona, as one markdown text.
//
// READ BY: the GetGuidance controller and the Hello handler, and nothing else.
// Hello sends the same document in its result so a session gets it without a
// second round trip (protocol.md §3), which is why the composition lives here
// rather than inside either caller: two ways of composing one document is how
// the handshake's copy and the command's copy drift apart.
// DEPENDS ON: the .md files in Documents/, and nothing else. No adapters, no
// macOS, no ports -- documents are pure resources.
//
// SPEC 0029 PART 4: THE SERVER STATES THE RULE AND THIS STATES THE INSTANCES.
// The rule ("a command that re-reads what is already there is in; a command that
// reaches what focus cannot is out") survives every platform. The instances do
// not survive even one -- and this reader is the proof, because the boundary
// falls in a DIFFERENT PLACE here than on NVDA: cursor navigation is an ordinary
// VoiceOver user's primary means of getting about, where its Windows analogue is
// an expert's escape hatch. A stance transcribed from the other bridge would
// forbid the thing this platform's own users do all day. That is the strongest
// argument this repo has for why the concrete half ships with the reader it
// describes.
//
// THE THIRD RENDERING OF THE EMBEDDED-DOCUMENT TRAP (root AGENTS.md, invariant
// 9), and each language fails differently:
//
//   * GO embeds at COMPILE time, so an edited document changes nothing until the
//     binary is rebuilt -- which is why scripts/doctor.py counts the server's
//     documents among its build inputs.
//   * PYTHON ships them in the .nvda-addon and reads them at run time, so they
//     must be in buildVars.bundledDataSources or scons will not rebuild.
//   * SWIFT resolves through `Bundle.module`, a bundle SwiftPM generates from the
//     `resources:` declaration in Package.swift. It is found automatically beside
//     an executable SwiftPM built; it is NOT found automatically inside a .app
//     that a script assembled, and whoever gives the app the bridge's dependency
//     edge (13.14) must copy that bundle into Contents/Resources in the same
//     breath. The failure is a runtime trap rather than a compile error, which is
//     why it is written here.
//
// A MISSING DOCUMENT RAISES; IT NEVER RETURNS "". An empty document reads to an
// agent as "this reader has nothing to say", which is a very different and much
// worse answer than "the build is broken" -- and the agent would act on it.

import Foundation

/// VoiceOver's own guidance, composed for one persona.
///
/// AN ENUM WITH STATIC MEMBERS RATHER THAN AN INSTANCE, because the documents are
/// process-wide constants: there is no per-session state here, nothing to inject,
/// and nothing that could differ between two sessions of the same build. That is
/// the same shape `LocalSocketPath` has, for the same reason.
public enum GuidanceDocuments {
	/// The section every persona gets: this reader's vocabulary, where its
	/// boundary falls, how state is read on a reader that cannot be asked, and the
	/// two cursors.
	static let common = "common"

	/// One document per persona the SERVER can currently declare (spec 0029). A
	/// value absent from this map is NOT an error -- see `guidance(for:)`.
	static let sections = [
		"user": "user",
		"validator": "validator",
		"expert": "expert",
	]

	/// What an unrecognised persona gets instead of a section: an explanation, so
	/// the agent knows what it is missing rather than silently believing it was
	/// instructed.
	static let unknown = "unknown"

	/// The guidance for `persona`, and whether this bridge recognised it.
	///
	/// `recognised == false` is an ORDINARY OUTCOME and never an error. The set of
	/// personas belongs to the server and can grow, and a bridge that refused an
	/// unfamiliar one would make adding a persona a synchronised release across
	/// every bridge in the field (protocol.md §4). Such a caller still gets the
	/// common section, which is the larger half of what it needed, plus a
	/// paragraph saying what is missing.
	///
	/// An EMPTY persona -- a server predating spec 0029 -- takes the same path,
	/// deliberately: from this side "I do not know that stance" and "you named no
	/// stance" call for the same document.
	public static func guidance(for persona: String) throws -> (text: String, recognised: Bool) {
		let section = sections[persona]
		let text = try read(common) + "\n" + read(section ?? unknown)
		return (text, section != nil)
	}

	/// Where the documents sit INSIDE the bundle.
	///
	/// `.copy` in Package.swift copies the directory rather than its contents, so
	/// the files are nested under their own name and a lookup at the bundle root
	/// finds nothing. Measured while writing this: the loader raised
	/// `common.md is missing`, which is the design working -- a `?? ""` here would
	/// have shipped an empty document to every agent that asked and said nothing
	/// to anybody. The subdirectory is named rather than flattened because the
	/// grouping is what makes `Entities/Documents/` a directory of documents in
	/// the source tree too.
	static let directory = "Documents"

	/// Read one document out of the resource bundle.
	///
	/// LOUD RATHER THAN EMPTY, on both failures it can have: a name the bundle
	/// does not carry, and a file that will not decode. Either means this build
	/// was assembled without its documents, which is a BUILD fault rather than a
	/// session fault -- and the whole point of this function is that an agent is
	/// never handed silence and left to conclude the reader had nothing to say.
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

/// A guidance document this build should carry and does not.
///
/// It names the DOCUMENT and the reason, because the two failures have different
/// fixes and the person reading the error is looking at a build rather than at a
/// session: a name the bundle lacks means the resource declaration or the copy
/// into the app is wrong, and a file that will not decode means the file itself
/// is.
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
