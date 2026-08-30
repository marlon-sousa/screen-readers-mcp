// ROLE: adapter -- IMPLEMENTS the SpeechSource domain port by reading the JSON
// lines the capture voice appends to its own container file.
//
// DEPENDS ON: the LineTailer seam, never on the filesystem directly, which is
// what makes every decision here testable with no extension and no reader.
// BUILT BY: VoiceOverAdapterFactory, once per session, from the path Wiring
// resolved. STARTED BY: the hello handler, against that session's SpeechBuffer.
//
// THE CONTAINER FILE IS THE ONLY DOOR, and this is not a fallback. A speech
// provider that holds `com.apple.security.network.client` is not rejected with an
// error: macOS registers it, launches it, builds its audio unit, and then never
// asks it for its voices, logging `Skipping network entitled extension` where
// nobody looks (spec 0041, B1). So there is no socket, no port and no XPC on
// this route -- there is a file the sandboxed extension appends to and an
// ordinary unsandboxed process reads with no entitlement and no App Group
// (B2). Every decision about that file lives in this class.
//
// THE DECISIONS, all of them, in one place so the list can be read against the
// tests:
//
//   1. WHICH LINES ARE UTTERANCES. The feed carries everything the provider
//      observes -- `audio-unit-created`, `allocate-render-resources`,
//      `speech-voices-read`, `cancel` -- and only `synthesize` is speech. A
//      cancel arrives before EVERY new utterance and is the normal path, not a
//      fault (spec 0041, A3), so mistaking one for speech would double the
//      buffer and put an empty entry between every real pair.
//   2. THE EXTENSION'S SEQUENCE COUNTER IS DISCARDED. It is in the line, it
//      looks trustworthy, and it restarts whenever the system relaunches the
//      extension, which it does freely. The SpeechBuffer numbers utterances
//      itself; see its header for what trusting these would cost.
//   3. THE WORDS ARE RE-DERIVED FROM THE SSML. The line also carries the
//      extension's own rendering in `text`, and this half asks SpeechText
//      instead, so what an agent reads back is decided by one tested entity on
//      this side of the door. The `text` field is used only when a line carries
//      no `ssml` at all -- losing an utterance is worse than rendering it the
//      other half's way.
//   4. A LINE THAT CANNOT BE READ IS SKIPPED, NOT THROWN. This runs on a
//      capture thread with no one to answer to, the feed is written by another
//      process, and one unparseable line must not end a session or stop the
//      lines after it.
//
// THE TIMESTAMP IS THE EXTENSION'S, NOT OURS. Every line carries `at`, stamped
// as it was written, so `emittedAt` means the instant of EMISSION and survives
// the file handoff intact -- including whatever the feed's tail latency turns out
// to be, which nobody has measured yet (spec 0046, open question 3). Reading the
// clock here instead would silently fold that latency into every stamp.

import Foundation
import VoiceOverBridgeDomain

public final class ContainerFileSpeechSource: SpeechSource {
	private let tailer: any LineTailer

	public init(tailer: any LineTailer) {
		self.tailer = tailer
	}

	public func start(_ buffer: SpeechBuffer) {
		tailer.start { line in
			guard let utterance = ContainerFileSpeechSource.utterance(from: line) else { return }
			buffer.append(utterance)
		}
	}

	public func stop() {
		tailer.stop()
	}

	/// One feed line to one captured utterance, or nil for a line that is not
	/// speech. Static and pure: the whole of decision 1 through 4 above.
	static func utterance(from line: String) -> CapturedUtterance? {
		guard let data = line.data(using: .utf8),
			let object = try? JSONSerialization.jsonObject(with: data),
			let fields = object as? [String: Any],
			fields["event"] as? String == synthesizeEvent
		else { return nil }

		let ssml = fields["ssml"] as? String ?? ""
		// Decision 3: the SSML is what this half renders; the extension's own
		// `text` is the fallback for a line that carried no SSML.
		let text = ssml.isEmpty ? (fields["text"] as? String ?? "") : SpeechText.plain(ofSsml: ssml)
		return CapturedUtterance(
			text: text,
			// Decision: `at` is seconds since the epoch, written by the producer.
			// A line without one reports 0, which renders as "no instant was
			// recorded" rather than as a moment that did not happen.
			emittedAt: fields["at"] as? Double ?? 0,
			ssml: ssml,
			voice: fields["voice"] as? String ?? ""
		)
	}

	/// The event kind that is an utterance. The kind strings are the capture
	/// voice's own vocabulary (`CaptureEvent.Kind`), and changing one there is a
	/// wire change to this class rather than a rename -- the two halves are
	/// separate processes that meet only at this file.
	private static let synthesizeEvent = "synthesize"
}

public extension ContainerFileSpeechSource {
	/// Where the capture voice appends, derived from the same rule the extension
	/// derives it from -- and DUPLICATED ON PURPOSE, for the reason
	/// `LocalSocketPath` mirrors the server's `local_socket.go`: two processes
	/// must compute one path from one published rule or they never meet, and the
	/// failure mode is a feed that stays empty on a machine where the reader is
	/// plainly talking.
	///
	/// Inside the sandbox the extension's own `NSHomeDirectory()` already IS its
	/// container, so it writes `<home>/voiceover-capture.jsonl` and the system
	/// puts that under `~/Library/Containers/<extension bundle id>/Data/`. This
	/// side is not sandboxed, so it spells the whole path out. `home` is passed
	/// in rather than read here, so this stays a pure function of values.
	static func containerFilePath(home: String) -> String {
		URL(fileURLWithPath: home)
			.appendingPathComponent("Library/Containers")
			.appendingPathComponent(captureExtensionBundleID)
			.appendingPathComponent("Data")
			.appendingPathComponent(captureFileName)
			.path
	}
}

/// The capture voice extension's bundle identifier, which names its container.
///
/// It still says `spike` because THE BUNDLE IDENTITY IS FROZEN: the voice
/// identifier VoiceOver stores is derived from it, so renaming costs every user
/// -- today, the maintainer -- a trip to VoiceOver Utility to re-select a voice
/// that silently vanished. `build.sh` builds the same string from `APP_ID`, and
/// 13.11 owns identifiers and is where that one-time cost is paid.
public let captureExtensionBundleID = "org.screen-readers-mcp.spike.capture.voice"

/// What the capture voice's audio unit DECLARES itself as -- and therefore what
/// the identifier the system publishes ENDS with, never what it equals.
///
/// The system prefixes the extension's bundle id, so the published string on the
/// machine this was measured on is
/// `org.screen-readers-mcp.spike.capture.voice.org.screen-readers-mcp.spike.capture`
/// (spec 0041, A1; spec 0047, finding 17). Anything resolving our voice matches
/// by SUFFIX for that reason, and the string actually written into the reader's
/// preference is the one the system published rather than one assembled here.
///
/// Duplicated from `CaptureVoice.ourVoiceIdentifier` on purpose, and frozen with
/// it: the bridge may not import the capture voice's module -- that module
/// depends on nothing of ours, in either direction -- and the two are one
/// contract between two processes, like the container path above.
public let captureVoiceIdentifierSuffix = "org.screen-readers-mcp.spike.capture"

/// The feed's file name, matching `captureLogPath` in the extension.
public let captureFileName = "voiceover-capture.jsonl"
