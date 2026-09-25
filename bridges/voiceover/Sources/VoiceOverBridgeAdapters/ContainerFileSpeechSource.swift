// ROLE: adapter implementing the SpeechSource port by reading the JSON lines the capture voice appends to its container file.
// BUILT BY: VoiceOverAdapterFactory, once per session.
// USED BY: the hello handler, which starts it against the session's SpeechBuffer.

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

	/// Nil for a line that is not a `synthesize` event or cannot be parsed.
	static func utterance(from line: String) -> CapturedUtterance? {
		guard let data = line.data(using: .utf8),
			let object = try? JSONSerialization.jsonObject(with: data),
			let fields = object as? [String: Any],
			fields["event"] as? String == synthesizeEvent
		else { return nil }

		let ssml = fields["ssml"] as? String ?? ""
		let text = ssml.isEmpty ? (fields["text"] as? String ?? "") : SpeechText.plain(ofSsml: ssml)
		return CapturedUtterance(
			text: text,
			// `at` is the extension's emission stamp in epoch seconds; 0 means the line carried none.
			emittedAt: fields["at"] as? Double ?? 0,
			ssml: ssml,
			voice: fields["voice"] as? String ?? ""
		)
	}

	/// Must match the capture voice's `CaptureEvent.Kind`: the two processes meet only at the feed file.
	private static let synthesizeEvent = "synthesize"
}

public extension ContainerFileSpeechSource {
	/// Must compute the path the extension writes (`<home>/voiceover-capture.jsonl` in its sandbox container), or the feed stays empty.
	static func containerFilePath(home: String) -> String {
		URL(fileURLWithPath: home)
			.appendingPathComponent("Library/Containers")
			.appendingPathComponent(captureExtensionBundleID)
			.appendingPathComponent("Data")
			.appendingPathComponent(captureFileName)
			.path
	}
}

/// The capture voice extension's bundle identifier; frozen, because VoiceOver's stored voice identifier derives from it and `build.sh` builds the same string from `APP_ID`.
public let captureExtensionBundleID = "org.screen-readers-mcp.spike.capture.voice"

/// What the capture voice's audio unit declares; the system prefixes the extension's bundle id, so match a published identifier by suffix.
/// Must match `CaptureVoice.ourVoiceIdentifier`, which the bridge cannot import.
public let captureVoiceIdentifierSuffix = "org.screen-readers-mcp.spike.capture"

/// The feed's file name, matching `captureLogPath` in the extension.
public let captureFileName = "voiceover-capture.jsonl"
